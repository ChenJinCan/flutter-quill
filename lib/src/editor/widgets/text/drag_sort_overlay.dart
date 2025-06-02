import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../controller/quill_controller.dart';
import 'swipe_manager.dart';

/// 用于存储TextLine位置信息的辅助类
class _LineInfo {
  final double top;
  final double bottom;
  final double height;

  _LineInfo({
    required this.top,
    required this.bottom,
    required this.height,
  });
}

/// 拖拽排序覆盖层 - 精简版本，模仿 Notion/Craft 交互
class DragSortOverlay {
  static OverlayEntry? _overlayEntry;
  static SwipeableComponent? _draggingComponent;
  static QuillController? _controller;
  static GlobalKey? _editorKey;
  static ScrollController? _scrollController;
  static BuildContext? _context;

  // 边缘滚动相关
  static Timer? _scrollTimer;
  static bool _isScrolling = false;
  static const double _edgeZone = 100.0; // 边缘检测区域
  static const double _scrollSpeed = 200.0; // 滚动速度（像素/秒）

  // 当前拖拽位置
  static Offset? _currentPosition;

  /// 显示拖拽覆盖层
  static void show({
    required BuildContext context,
    required SwipeableComponent component,
    required QuillController controller,
    required GlobalKey editorKey,
    required Offset initialGlobalPosition,
    ScrollController? scrollController,
  }) {
    hide(); // 确保之前的覆盖层被移除

    _draggingComponent = component;
    _controller = controller;
    _editorKey = editorKey;
    _scrollController = scrollController;
    _currentPosition = initialGlobalPosition;
    _context = context;

    _overlayEntry = OverlayEntry(
      builder: (context) => _DragOverlayWidget(
        component: component,
        controller: controller,
        editorKey: editorKey,
        initialPosition: initialGlobalPosition,
        scrollController: scrollController,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 隐藏拖拽覆盖层
  static void hide() {
    _stopEdgeScroll();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _draggingComponent = null;
    _controller = null;
    _editorKey = null;
    _scrollController = null;
    _currentPosition = null;
    _context = null;
  }

  /// 更新拖拽位置
  static void updatePosition(Offset globalPosition) {
    _currentPosition = globalPosition;
    _checkEdgeScroll(globalPosition);
    _overlayEntry?.markNeedsBuild();
  }

  /// 获取准确的AppBar高度
  static double _getAppBarHeight() {
    if (_context == null) return 56.0;

    try {
      final scaffold = Scaffold.maybeOf(_context!);
      if (scaffold != null) {
        final appBar = scaffold.widget.appBar;
        if (appBar != null) {
          return appBar.preferredSize.height;
        }

        // 尝试通过祖先查找AppBar
        final appBarElement = _context!.findAncestorWidgetOfExactType<AppBar>();
        if (appBarElement != null) {
          return appBarElement.preferredSize.height;
        }
      }
    } catch (e) {
      // 静默处理错误
    }

    return 56.0; // 默认AppBar高度
  }

  /// 检查边缘滚动
  static void _checkEdgeScroll(Offset position) {
    if (_scrollController == null ||
        !_scrollController!.hasClients ||
        _context == null) {
      return;
    }

    final mediaQuery = MediaQuery.of(_context!);
    final screenHeight = mediaQuery.size.height;
    final safeAreaTop = mediaQuery.padding.top;
    final safeAreaBottom = mediaQuery.padding.bottom;
    final appBarHeight = _getAppBarHeight();

    // 计算实际可用区域
    final effectiveTop = safeAreaTop + appBarHeight;
    final effectiveBottom = screenHeight - safeAreaBottom;

    bool shouldScrollUp = position.dy < effectiveTop + _edgeZone;
    bool shouldScrollDown = position.dy > effectiveBottom - _edgeZone;

    if (shouldScrollUp || shouldScrollDown) {
      _startEdgeScroll(shouldScrollUp ? -1 : 1);
    } else {
      _stopEdgeScroll();
    }
  }

  /// 开始边缘滚动
  static void _startEdgeScroll(int direction) {
    if (_isScrolling) return;

    _isScrolling = true;
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollController == null || !_scrollController!.hasClients) {
        _stopEdgeScroll();
        return;
      }

      final currentOffset = _scrollController!.offset;
      final maxOffset = _scrollController!.position.maxScrollExtent;
      final scrollDelta = _scrollSpeed * 0.016 * direction; // 60fps

      double newOffset = (currentOffset + scrollDelta).clamp(0.0, maxOffset);

      if (newOffset != currentOffset) {
        _scrollController!.jumpTo(newOffset);
      }

      // 重新检查当前位置是否还在边缘
      if (_currentPosition != null && _context != null) {
        final mediaQuery = MediaQuery.of(_context!);
        final screenHeight = mediaQuery.size.height;
        final safeAreaTop = mediaQuery.padding.top;
        final safeAreaBottom = mediaQuery.padding.bottom;
        final appBarHeight = _getAppBarHeight();

        final effectiveTop = safeAreaTop + appBarHeight;
        final effectiveBottom = screenHeight - safeAreaBottom;

        bool stillInEdge = _currentPosition!.dy < effectiveTop + _edgeZone ||
            _currentPosition!.dy > effectiveBottom - _edgeZone;

        if (!stillInEdge) {
          _stopEdgeScroll();
        }
      }
    });
  }

  /// 停止边缘滚动
  static void _stopEdgeScroll() {
    _isScrolling = false;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }
}

/// 拖拽覆盖层组件
class _DragOverlayWidget extends StatefulWidget {
  const _DragOverlayWidget({
    required this.component,
    required this.controller,
    required this.editorKey,
    required this.initialPosition,
    required this.scrollController,
  });

  final SwipeableComponent component;
  final QuillController controller;
  final GlobalKey editorKey;
  final Offset initialPosition;
  final ScrollController? scrollController;

  @override
  State<_DragOverlayWidget> createState() => _DragOverlayWidgetState();
}

class _DragOverlayWidgetState extends State<_DragOverlayWidget> {
  Offset? _insertIndicatorPosition;

  // 缓存LineInfo，避免重复计算
  List<_LineInfo>? _cachedLineInfos;
  Size? _lastEditorSize;
  int? _lastDocumentHash;
  double? _lastScrollOffset;

  @override
  void initState() {
    super.initState();
    // 监听滚动变化，在滚动时清除缓存
    widget.scrollController?.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScrollChanged);
    super.dispose();
  }

  /// 滚动位置改变时清除缓存
  void _onScrollChanged() {
    final currentScrollOffset = widget.scrollController?.offset;
    if (currentScrollOffset != _lastScrollOffset) {
      _cachedLineInfos = null;
      _lastScrollOffset = currentScrollOffset;

      // 如果正在显示指示器，立即更新
      if (_insertIndicatorPosition != null &&
          DragSortOverlay._currentPosition != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _updateInsertIndicator(DragSortOverlay._currentPosition!);
          }
        });
      }
    }
  }

  /// 获取文档哈希值，用于检测文档变化
  int _getDocumentHash() {
    final doc = widget.controller.document;
    return doc.length.hashCode ^ doc.root.children.length.hashCode;
  }

  /// 检查是否需要重新计算LineInfo
  bool _shouldRecalculateLineInfos(RenderBox editorRenderBox) {
    final currentEditorSize = editorRenderBox.size;
    final currentDocumentHash = _getDocumentHash();
    final currentScrollOffset = widget.scrollController?.offset;

    if (_cachedLineInfos == null) return true;
    if (_lastEditorSize != currentEditorSize) return true;
    if (_lastDocumentHash != currentDocumentHash) return true;
    if (_lastScrollOffset != currentScrollOffset) return true;

    return false;
  }

  /// 获取或计算LineInfo
  List<_LineInfo> _getLineInfos(RenderBox editorRenderBox) {
    if (_shouldRecalculateLineInfos(editorRenderBox)) {
      final lineInfos = <_LineInfo>[];
      _collectTextLineInfos(editorRenderBox, Offset.zero, lineInfos);

      // 按Y位置排序
      lineInfos.sort((a, b) => a.top.compareTo(b.top));

      // 缓存结果
      _cachedLineInfos = lineInfos;
      _lastEditorSize = editorRenderBox.size;
      _lastDocumentHash = _getDocumentHash();
      _lastScrollOffset = widget.scrollController?.offset;
    }

    return _cachedLineInfos!;
  }

  /// 递归收集TextLine位置信息
  void _collectTextLineInfos(
      RenderBox renderBox, Offset offset, List<_LineInfo> lineInfos) {
    renderBox.visitChildren((child) {
      if (child is RenderBox) {
        final childParentData = child.parentData;
        if (childParentData is BoxParentData) {
          final childOffset = offset + childParentData.offset;

          if (_isTextLineRenderBox(child)) {
            // 这是TextLine，记录位置信息
            final lineInfo = _LineInfo(
              top: childOffset.dy,
              bottom: childOffset.dy + child.size.height,
              height: child.size.height,
            );
            lineInfos.add(lineInfo);
          } else {
            // 递归检查子组件
            _collectTextLineInfos(child, childOffset, lineInfos);
          }
        }
      }
    });
  }

  /// 检查是否是TextLine
  bool _isTextLineRenderBox(RenderBox renderBox) {
    return renderBox.runtimeType.toString().contains('TextLine');
  }

  @override
  Widget build(BuildContext context) {
    final currentPos =
        DragSortOverlay._currentPosition ?? widget.initialPosition;

    // 计算插入指示器位置
    _updateInsertIndicator(currentPos);

    return Stack(
      children: [
        // 插入位置指示器
        if (_insertIndicatorPosition != null)
          Positioned(
            left: 20,
            right: 20,
            top: _insertIndicatorPosition!.dy - 1,
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withOpacity(0.3),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          ),

        // 拖拽预览
        Positioned(
          left: currentPos.dx - 150,
          top: currentPos.dy - 20,
          child: IgnorePointer(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 300),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                widget.component.textContent.trim().isEmpty
                    ? '空行'
                    : widget.component.textContent.trim(),
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 更新插入指示器位置 - 使用精确的LineInfo计算
  void _updateInsertIndicator(Offset globalPosition) {
    final renderObject = widget.editorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    try {
      final editorGlobalPosition = renderObject.localToGlobal(Offset.zero);
      final editorLocalPosition = renderObject.globalToLocal(globalPosition);
      final editorSize = renderObject.size;

      // 确保拖拽位置在编辑器范围内
      if (editorLocalPosition.dy < 0 ||
          editorLocalPosition.dy > editorSize.height) {
        setState(() {
          _insertIndicatorPosition = null;
        });
        return;
      }

      // 获取精确的LineInfo
      final lineInfos = _getLineInfos(renderObject);
      final insertionY = _findBestInsertionPosition(
          lineInfos, editorLocalPosition.dy, editorGlobalPosition);

      if (insertionY != null) {
        setState(() {
          _insertIndicatorPosition = Offset(0, insertionY);
        });
      } else {
        setState(() {
          _insertIndicatorPosition = null;
        });
      }
    } catch (e) {
      setState(() {
        _insertIndicatorPosition = null;
      });
    }
  }

  /// 找到最佳插入位置 - 精确计算TextLine间隙
  double? _findBestInsertionPosition(
      List<_LineInfo> lineInfos, double dragY, Offset editorGlobalPosition) {
    if (lineInfos.isEmpty) return null;

    const insertionMargin = 20.0;

    // 在第一行之前
    if (dragY < lineInfos.first.top + insertionMargin) {
      return editorGlobalPosition.dy + lineInfos.first.top - 8;
    }

    // 在最后一行之后
    if (dragY > lineInfos.last.bottom - insertionMargin) {
      return editorGlobalPosition.dy + lineInfos.last.bottom + 8;
    }

    // 在TextLine之间找最合适的位置
    for (int i = 0; i < lineInfos.length - 1; i++) {
      final currentLine = lineInfos[i];
      final nextLine = lineInfos[i + 1];

      final gapTop = currentLine.bottom;
      final gapBottom = nextLine.top;
      final gapCenter = (gapTop + gapBottom) / 2;

      // 拖拽位置在间隙中
      if (dragY >= gapTop && dragY <= gapBottom) {
        return editorGlobalPosition.dy + gapCenter;
      }

      // 拖拽位置在当前行中，找最近的间隙
      if (dragY >= currentLine.top && dragY <= currentLine.bottom) {
        final distanceToTopGap = i > 0
            ? (dragY - (lineInfos[i - 1].bottom + currentLine.top) / 2).abs()
            : double.infinity;
        final distanceToBottomGap = (dragY - gapCenter).abs();

        if (distanceToTopGap < distanceToBottomGap && i > 0) {
          final topGapCenter = (lineInfos[i - 1].bottom + currentLine.top) / 2;
          return editorGlobalPosition.dy + topGapCenter;
        } else {
          return editorGlobalPosition.dy + gapCenter;
        }
      }
    }

    // 默认插入到末尾
    return editorGlobalPosition.dy + lineInfos.last.bottom + 8;
  }
}
