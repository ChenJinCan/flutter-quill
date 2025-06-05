import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../controller/quill_controller.dart';
import '../../../document/document.dart';
import '../../../document/nodes/line.dart';
import '../../../document/nodes/block.dart';
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

/// 用于存储插入位置结果的辅助类
class _InsertionResult {
  final double insertionY;
  final int documentOffset;

  _InsertionResult(this.insertionY, this.documentOffset);
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
  static const double _edgeZone = 150.0; // 边缘检测区域
  static const double _scrollSpeed = 200.0; // 滚动速度（像素/秒）

  // 当前拖拽位置
  static Offset? _currentPosition;

  // 拖拽插入位置（文档偏移量）
  static int? _insertionOffset;

  /// 显示拖拽覆盖层
  static void show({
    required BuildContext context,
    required SwipeableComponent component,
    required QuillController controller,
    required GlobalKey editorKey,
    required Offset initialGlobalPosition,
    ScrollController? scrollController,
  }) {
    // 检查是否有其他组件在滑动 - 如果有则不显示拖拽覆盖层
    final swipeManager = SwipeStateManager();
    if (swipeManager.currentSwipingComponent != null &&
        swipeManager.currentSwipingComponent != component) {
      debugPrint('DragSortOverlay.show: 有其他组件在滑动，不显示拖拽覆盖层');
      return;
    }

    hide(); // 确保之前的覆盖层被移除

    _draggingComponent = component;
    _controller = controller;
    _editorKey = editorKey;
    _scrollController = scrollController;
    _currentPosition = initialGlobalPosition;
    _context = context;
    _insertionOffset = null;

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

  /// 检查覆盖层是否可见
  static bool get isVisible => _overlayEntry != null;

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
    _insertionOffset = null;
  }

  /// 更新拖拽位置
  static void updatePosition(Offset globalPosition) {
    _currentPosition = globalPosition;
    _checkEdgeScroll(globalPosition);
    _overlayEntry?.markNeedsBuild();
  }

  /// 完成拖拽排序操作
  static void completeDragSort() {
    debugPrint('DragSortOverlay.completeDragSort: 开始检查参数');
    debugPrint('  _draggingComponent: ${_draggingComponent?.componentId}');
    debugPrint('  _controller: ${_controller != null}');
    debugPrint('  _insertionOffset: $_insertionOffset');

    if (_draggingComponent == null ||
        _controller == null ||
        _insertionOffset == null) {
      debugPrint('DragSortOverlay.completeDragSort: 缺少必要参数');
      hide();
      return;
    }

    try {
      _performDocumentReorder(
          _draggingComponent!, _controller!, _insertionOffset!);
    } catch (e) {
      debugPrint('DragSortOverlay.completeDragSort: 拖拽排序失败: $e');
    } finally {
      hide();
    }
  }

  /// 执行文档重排序
  static void _performDocumentReorder(SwipeableComponent component,
      QuillController controller, int insertionOffset) {
    // 获取拖拽组件的信息
    final sourceOffset = component.documentOffset;
    final sourceLength = component.documentLength;

    // 如果插入位置在原位置范围内，不需要移动
    if (insertionOffset >= sourceOffset &&
        insertionOffset <= sourceOffset + sourceLength) {
      debugPrint('DragSortOverlay._performDocumentReorder: 插入位置在原位置范围内，无需移动');
      return;
    }

    debugPrint('DragSortOverlay._performDocumentReorder: 开始重排序');
    debugPrint('  源位置: $sourceOffset, 长度: $sourceLength');
    debugPrint('  目标位置: $insertionOffset');

    // Step 1: 提取完整的 TextLine Delta（包含所有格式和属性）
    final completeLineDelta = controller.document
        .toDelta()
        .slice(sourceOffset, sourceOffset + sourceLength);

    final textContent =
        controller.document.getPlainText(sourceOffset, sourceLength);
    debugPrint('  移动的文本: "${textContent.trim()}"');

    // Step 2: 设置 skipRequestKeyboard 避免自动聚焦键盘
    final originalSkipRequestKeyboard = controller.skipRequestKeyboard;
    controller.skipRequestKeyboard = true;

    // Step 3: 计算调整后的插入位置
    int adjustedInsertionOffset = insertionOffset;
    if (insertionOffset > sourceOffset) {
      // 如果插入位置在删除位置之后，需要减去删除的长度
      adjustedInsertionOffset = insertionOffset - sourceLength;
    }

    try {
      // Step 4: 删除原始位置的完整内容（包括换行符）
      controller.replaceText(sourceOffset, sourceLength, '', null,
          shouldNotifyListeners: false);

      debugPrint('  调整后的插入位置: $adjustedInsertionOffset');

      // Step 5: 在新位置插入完整的 TextLine Delta
      // 确保插入位置不超出文档范围
      final documentLength = controller.document.length;
      if (adjustedInsertionOffset >= documentLength) {
        adjustedInsertionOffset = documentLength;
      } else if (adjustedInsertionOffset < 0) {
        adjustedInsertionOffset = 0;
      }

      // Step 6: 插入内容，避免自动聚焦
      controller.replaceText(
          adjustedInsertionOffset, 0, completeLineDelta, null,
          shouldNotifyListeners: true);
    } finally {
      // 恢复原始的 skipRequestKeyboard 状态
      controller.skipRequestKeyboard = originalSkipRequestKeyboard;
    }

    debugPrint(
        'DragSortOverlay._performDocumentReorder: 重排序完成，插入位置: $adjustedInsertionOffset');
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
    final effectiveBottom = screenHeight;

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
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 8), (timer) {
      if (_scrollController == null || !_scrollController!.hasClients) {
        _stopEdgeScroll();
        return;
      }

      // 重新检查当前位置是否还在边缘 - 这是唯一的停止条件
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
          return;
        }
      }

      // 持续滚动，不管是否到达边界
      final currentOffset = _scrollController!.offset;
      final maxOffset = _scrollController!.position.maxScrollExtent;
      final scrollDelta = _scrollSpeed * 0.032 * direction; // 125fps

      double targetOffset = currentOffset + scrollDelta;

      // 确定实际的滚动目标位置
      double newOffset;
      if (direction < 0) {
        // 向上滚动：目标是0
        newOffset = targetOffset < 0 ? 0 : targetOffset;
      } else {
        // 向下滚动：目标是maxOffset
        newOffset = targetOffset > maxOffset ? maxOffset : targetOffset;
      }

      // 总是尝试滚动，即使已经在边界
      try {
        _scrollController!.jumpTo(newOffset);
      } catch (e) {
        // 滚动失败才停止
        _stopEdgeScroll();
        return;
      }

      // 注意：不再检查 newOffset != currentOffset
      // 因为即使到达边界，只要拖拽还在边缘区域，就应该保持滚动状态
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
    if (renderObject is! RenderBox) {
      debugPrint('_updateInsertIndicator: renderObject 不是 RenderBox');
      return;
    }

    try {
      final editorGlobalPosition = renderObject.localToGlobal(Offset.zero);
      final editorLocalPosition = renderObject.globalToLocal(globalPosition);
      final editorSize = renderObject.size;

      debugPrint('_updateInsertIndicator: globalPosition=$globalPosition');
      debugPrint(
          '_updateInsertIndicator: editorLocalPosition=$editorLocalPosition');
      debugPrint('_updateInsertIndicator: editorSize=$editorSize');

      // 确保拖拽位置在编辑器范围内
      if (editorLocalPosition.dy < 0 ||
          editorLocalPosition.dy > editorSize.height) {
        debugPrint('_updateInsertIndicator: 拖拽位置超出编辑器范围');
        setState(() {
          _insertIndicatorPosition = null;
        });
        DragSortOverlay._insertionOffset = null;
        return;
      }

      // 获取精确的LineInfo
      final lineInfos = _getLineInfos(renderObject);
      debugPrint('_updateInsertIndicator: 找到 ${lineInfos.length} 行');

      final result = _findBestInsertionPosition(
          lineInfos, editorLocalPosition.dy, editorGlobalPosition);

      if (result != null) {
        debugPrint(
            '_updateInsertIndicator: 设置插入位置 offset=${result.documentOffset}, y=${result.insertionY}');
        setState(() {
          _insertIndicatorPosition = Offset(0, result.insertionY);
        });
        DragSortOverlay._insertionOffset = result.documentOffset;
      } else {
        debugPrint('_updateInsertIndicator: 未找到插入位置');
        setState(() {
          _insertIndicatorPosition = null;
        });
        DragSortOverlay._insertionOffset = null;
      }
    } catch (e) {
      debugPrint('_updateInsertIndicator: 发生异常: $e');
      setState(() {
        _insertIndicatorPosition = null;
      });
      DragSortOverlay._insertionOffset = null;
    }
  }

  /// 找到最佳插入位置 - 精确计算TextLine间隙
  _InsertionResult? _findBestInsertionPosition(
      List<_LineInfo> lineInfos, double dragY, Offset editorGlobalPosition) {
    if (lineInfos.isEmpty) return null;

    const insertionMargin = 20.0;

    // 在第一行之前
    if (dragY < lineInfos.first.top + insertionMargin) {
      final insertionY = editorGlobalPosition.dy + lineInfos.first.top - 8;
      final documentOffset = _getDocumentOffsetForLineIndex(0);
      return _InsertionResult(insertionY, documentOffset);
    }

    // 在最后一行之后
    if (dragY > lineInfos.last.bottom - insertionMargin) {
      final insertionY = editorGlobalPosition.dy + lineInfos.last.bottom + 8;
      final documentOffset = _getDocumentOffsetForLineIndex(lineInfos.length);
      return _InsertionResult(insertionY, documentOffset);
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
        final insertionY = editorGlobalPosition.dy + gapCenter;
        final documentOffset = _getDocumentOffsetForLineIndex(i + 1);
        return _InsertionResult(insertionY, documentOffset);
      }

      // 拖拽位置在当前行中，找最近的间隙
      if (dragY >= currentLine.top && dragY <= currentLine.bottom) {
        final distanceToTopGap = i > 0
            ? (dragY - (lineInfos[i - 1].bottom + currentLine.top) / 2).abs()
            : double.infinity;
        final distanceToBottomGap = (dragY - gapCenter).abs();

        if (distanceToTopGap < distanceToBottomGap && i > 0) {
          final topGapCenter = (lineInfos[i - 1].bottom + currentLine.top) / 2;
          final insertionY = editorGlobalPosition.dy + topGapCenter;
          final documentOffset = _getDocumentOffsetForLineIndex(i);
          return _InsertionResult(insertionY, documentOffset);
        } else {
          final insertionY = editorGlobalPosition.dy + gapCenter;
          final documentOffset = _getDocumentOffsetForLineIndex(i + 1);
          return _InsertionResult(insertionY, documentOffset);
        }
      }
    }

    // 默认插入到末尾
    final insertionY = editorGlobalPosition.dy + lineInfos.last.bottom + 8;
    final documentOffset = _getDocumentOffsetForLineIndex(lineInfos.length);
    return _InsertionResult(insertionY, documentOffset);
  }

  /// 根据行索引获取文档偏移量
  int _getDocumentOffsetForLineIndex(int lineIndex) {
    try {
      final document = widget.controller.document;
      int currentLineIndex = 0;
      int documentOffset = 0;

      for (final node in document.root.children) {
        if (node is Line) {
          if (currentLineIndex == lineIndex) {
            return documentOffset;
          }
          currentLineIndex++;
          documentOffset += node.length;
        } else if (node is Block) {
          for (final line in node.children.cast<Line>()) {
            if (currentLineIndex == lineIndex) {
              return documentOffset;
            }
            currentLineIndex++;
            documentOffset += line.length;
          }
        }
      }

      // 如果超出范围，返回文档长度（末尾）
      return document.length;
    } catch (e) {
      debugPrint('_getDocumentOffsetForLineIndex error: $e');
      return widget.controller.document.length;
    }
  }
}
