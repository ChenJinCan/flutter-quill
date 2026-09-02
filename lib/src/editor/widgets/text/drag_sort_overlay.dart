import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../controller/quill_controller.dart';
import '../../../document/nodes/block.dart';
import '../../../document/nodes/line.dart';
import 'drag_sort_diagnostics.dart';
import 'swipe_manager.dart';

class _LineInfo {
  _LineInfo({
    required this.top,
    required this.bottom,
    required this.height,
  });
  final double top;
  final double bottom;
  final double height;
}

class _InsertionResult {
  _InsertionResult(this.insertionY, this.documentOffset);
  final double insertionY;
  final int documentOffset;
}

/// 拖拽排序覆盖层
class DragSortOverlay {
  static OverlayEntry? _overlayEntry;
  static SwipeableComponent? _draggingComponent;
  static QuillController? _controller;
  static ScrollController? _scrollController;
  static BuildContext? _context;
  static Offset? _currentPosition;
  static int? _insertionOffset;

  // 边缘滚动相关
  static Timer? _scrollTimer;
  static bool _isAutoScrolling = false;
  static const double _edgeZone = 100;
  static const double _baseScrollSpeed = 800;
  static const double _maxScrollSpeed = 3000;
  static double _currentScrollVelocity = 0;

  /// 显示拖拽覆盖层
  static void show({
    required BuildContext context,
    required SwipeableComponent component,
    required QuillController controller,
    required GlobalKey editorKey,
    required Offset initialGlobalPosition,
    ScrollController? scrollController,
  }) {
    final swipeManager = SwipeStateManager();
    if (swipeManager.currentSwipingComponent != null &&
        swipeManager.currentSwipingComponent != component) {
      QuillDragSortDiagnostics.event(
        phase: 'overlay_show',
        result: 'rejected',
        reason: 'another_component_swiping',
      );
      return;
    }

    hide();
    _stopAutoScroll();

    _draggingComponent = component;
    _controller = controller;
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
    QuillDragSortDiagnostics.event(phase: 'overlay_show', result: 'success');
  }

  static bool get isVisible => _overlayEntry != null;

  /// 隐藏拖拽覆盖层
  static void hide() {
    _stopAutoScroll();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _draggingComponent = null;
    _controller = null;
    _scrollController = null;
    _currentPosition = null;
    _context = null;
    _insertionOffset = null;
  }

  static void hideOnFocus() {
    if (isVisible) hide();
  }

  /// 更新拖拽位置
  static void updatePosition(Offset globalPosition) {
    _currentPosition = globalPosition;
    _handleEdgeScrolling(globalPosition);
    _overlayEntry?.markNeedsBuild();
  }

  /// 获取滚动能力
  static (bool, bool) _getScrollCapabilities() {
    if (_scrollController == null || !_scrollController!.hasClients) {
      return (false, false);
    }

    final currentOffset = _scrollController!.offset;
    final maxOffset = _scrollController!.position.maxScrollExtent;
    return (currentOffset > 0, currentOffset < maxOffset);
  }

  /// 处理边缘滚动 - 确保同一时间只有一个滚动方向
  static void _handleEdgeScrolling(Offset position) {
    if (_scrollController == null ||
        !_scrollController!.hasClients ||
        _context == null) {
      return;
    }

    final mediaQuery = MediaQuery.of(_context!);
    final effectiveTop = mediaQuery.padding.top + _getAppBarHeight();
    final effectiveBottom = mediaQuery.size.height - mediaQuery.padding.bottom;

    final distanceFromScreenTop = position.dy - effectiveTop;
    final distanceFromScreenBottom = effectiveBottom - position.dy;

    // 边缘检测逻辑：
    // - 顶部及以上都应该触发向上滚动（distanceFromScreenTop <= _edgeZone）
    // - 底部及以下都应该触发向下滚动（distanceFromScreenBottom <= _edgeZone）
    final inTopScrollZone = distanceFromScreenTop <= _edgeZone;
    final inBottomScrollZone = distanceFromScreenBottom <= _edgeZone;

    final (canScrollUp, canScrollDown) = _getScrollCapabilities();

    int desiredDirection = 0;
    double distance = 0;

    // 确定滚动方向和距离
    if (inTopScrollZone && inBottomScrollZone) {
      // 同时在两个区域，选择距离更近的一个
      if (distanceFromScreenTop <= distanceFromScreenBottom && canScrollUp) {
        desiredDirection = -1;
        distance = distanceFromScreenTop.clamp(0.0, double.infinity);
      } else if (canScrollDown) {
        desiredDirection = 1;
        distance = distanceFromScreenBottom.clamp(0.0, double.infinity);
      }
    } else if (inTopScrollZone && canScrollUp) {
      desiredDirection = -1;
      distance = distanceFromScreenTop.clamp(0.0, double.infinity);
    } else if (inBottomScrollZone && canScrollDown) {
      desiredDirection = 1;
      distance = distanceFromScreenBottom.clamp(0.0, double.infinity);
    }

    if (desiredDirection != 0) {
      final speedRatio = 1.0 - (distance / _edgeZone);
      _currentScrollVelocity = desiredDirection *
          (_baseScrollSpeed +
              (_maxScrollSpeed - _baseScrollSpeed) * speedRatio);
      _startAutoScroll();
    } else if (_isAutoScrolling) {
      _stopAutoScroll();
    }
  }

  /// 完成拖拽排序操作
  static void completeDragSort() {
    if (_draggingComponent == null ||
        _controller == null ||
        _insertionOffset == null) {
      QuillDragSortDiagnostics.event(
        phase: 'sort_commit',
        result: 'skipped',
        reason: 'missing_drag_state',
      );
      hide();
      return;
    }

    try {
      _performDocumentReorder(
          _draggingComponent!, _controller!, _insertionOffset!);
      QuillDragSortDiagnostics.event(phase: 'sort_commit', result: 'success');
    } catch (e) {
      QuillDragSortDiagnostics.event(
        phase: 'sort_commit',
        result: 'failure',
        reason: 'exception_${e.runtimeType}',
      );
    } finally {
      hide();
    }
  }

  /// 执行文档重排序
  static void _performDocumentReorder(SwipeableComponent component,
      QuillController controller, int insertionOffset) {
    final sourceOffset = component.documentOffset;
    final sourceLength = component.documentLength;

    if (insertionOffset >= sourceOffset &&
        insertionOffset <= sourceOffset + sourceLength) {
      return;
    }

    final completeLineDelta = controller.document
        .toDelta()
        .slice(sourceOffset, sourceOffset + sourceLength);

    // 检查Delta是否为空
    if (completeLineDelta.isEmpty) {
      return;
    }

    final originalSkipRequestKeyboard = controller.skipRequestKeyboard;
    controller.skipRequestKeyboard = true;

    // 记录原始文档长度
    final originalDocumentLength = controller.document.length;

    int adjustedInsertionOffset = insertionOffset;
    if (insertionOffset > sourceOffset) {
      adjustedInsertionOffset = insertionOffset - sourceLength;
    }

    try {
      // 先删除源内容
      controller.replaceText(sourceOffset, sourceLength, '', null,
          shouldNotifyListeners: false);

      // 获取删除后的文档长度
      final documentLength = controller.document.length;

      // 特殊处理：如果原始插入位置等于文档长度（拖拽到底部），
      // 删除后应该插入到新的文档末尾
      if (insertionOffset == originalDocumentLength) {
        adjustedInsertionOffset = documentLength;
      } else {
        // 否则，确保插入位置在有效范围内
        adjustedInsertionOffset =
            adjustedInsertionOffset.clamp(0, documentLength);
      }

      // 执行插入操作
      controller.replaceText(
          adjustedInsertionOffset, 0, completeLineDelta, null,
          shouldNotifyListeners: true);
    } finally {
      controller.skipRequestKeyboard = originalSkipRequestKeyboard;
    }
  }

  /// 获取AppBar高度
  static double _getAppBarHeight() {
    if (_context == null) return 56;

    try {
      final scaffold = Scaffold.maybeOf(_context!);
      if (scaffold?.widget.appBar != null) {
        return scaffold!.widget.appBar!.preferredSize.height;
      }
      final appBar = _context!.findAncestorWidgetOfExactType<AppBar>();
      if (appBar != null) {
        return appBar.preferredSize.height;
      }
    } catch (e) {
      // 静默处理错误
    }
    return 56;
  }

  /// 开始自动滚动
  static void _startAutoScroll() {
    if (_isAutoScrolling) return;

    _isAutoScrolling = true;
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollController == null || !_scrollController!.hasClients) {
        _stopAutoScroll();
        return;
      }

      final currentOffset = _scrollController!.offset;
      final maxOffset = _scrollController!.position.maxScrollExtent;

      if ((_currentScrollVelocity < 0 && currentOffset <= 0) ||
          (_currentScrollVelocity > 0 && currentOffset >= maxOffset)) {
        _stopAutoScroll();
        return;
      }

      final scrollDelta = _currentScrollVelocity * 0.016;
      final clampedDelta = scrollDelta.clamp(-20.0, 20.0);
      final newOffset = (currentOffset + clampedDelta).clamp(0.0, maxOffset);

      if ((newOffset - currentOffset).abs() >= 0.1) {
        _scrollController!.jumpTo(newOffset);
      }
    });
  }

  /// 停止自动滚动
  static void _stopAutoScroll() {
    _isAutoScrolling = false;
    _currentScrollVelocity = 0;
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

  @override
  void initState() {
    super.initState();
    widget.scrollController?.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    widget.scrollController?.removeListener(_onScrollChanged);
    super.dispose();
  }

  void _onScrollChanged() {
    if (DragSortOverlay._currentPosition != null && mounted) {
      setState(() {});
    }
  }

  /// 获取LineInfo
  List<_LineInfo> _getLineInfos(RenderBox editorRenderBox) {
    final lineInfos = <_LineInfo>[];
    _collectTextLineInfos(editorRenderBox, Offset.zero, lineInfos);
    lineInfos.sort((a, b) => a.top.compareTo(b.top));
    return lineInfos;
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

    // 立即同步更新插入指示器位置
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
                    color: Colors.blue.withValues(alpha: 0.3),
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
            child: _buildDragPreview(widget.component.textContent),
          ),
        ),
      ],
    );
  }

  /// 更新插入指示器位置
  void _updateInsertIndicator(Offset globalPosition) {
    final renderObject = widget.editorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    try {
      final editorGlobalPosition = renderObject.localToGlobal(Offset.zero);
      final editorLocalPosition = renderObject.globalToLocal(globalPosition);
      final editorSize = renderObject.size;
      final lineInfos = _getLineInfos(renderObject);

      _InsertionResult? result;

      if (editorLocalPosition.dy < -50) {
        result = _InsertionResult(globalPosition.dy, 0);
      } else if (editorLocalPosition.dy > editorSize.height + 50) {
        result = _InsertionResult(
            globalPosition.dy, widget.controller.document.length);
      } else {
        result = _findBestInsertionPosition(lineInfos, editorLocalPosition.dy,
            editorGlobalPosition, globalPosition);
      }

      if (result != null && mounted) {
        setState(() {
          _insertIndicatorPosition = Offset(0, result!.insertionY);
        });
        DragSortOverlay._insertionOffset = result.documentOffset;
      } else if (mounted) {
        setState(() {
          _insertIndicatorPosition = null;
        });
        DragSortOverlay._insertionOffset = null;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _insertIndicatorPosition = null;
        });
      }
      DragSortOverlay._insertionOffset = null;
    }
  }

  /// 找到最佳插入位置
  _InsertionResult? _findBestInsertionPosition(List<_LineInfo> lineInfos,
      double dragY, Offset editorGlobalPosition, Offset globalDragPosition) {
    if (lineInfos.isEmpty) {
      return _InsertionResult(globalDragPosition.dy, 0);
    }

    const insertionMargin = 15.0;

    // 在第一行之前
    if (dragY < lineInfos.first.top + insertionMargin) {
      final insertionY = editorGlobalPosition.dy + lineInfos.first.top - 5;
      return _InsertionResult(insertionY, _getDocumentOffsetForLineIndex(0));
    }

    // 在最后一行之后
    if (dragY > lineInfos.last.bottom - insertionMargin) {
      return _InsertionResult(globalDragPosition.dy,
          _getDocumentOffsetForLineIndex(lineInfos.length));
    }

    // 在TextLine之间找最合适的位置
    for (int i = 0; i < lineInfos.length - 1; i++) {
      final currentLine = lineInfos[i];
      final nextLine = lineInfos[i + 1];
      final gapCenter = (currentLine.bottom + nextLine.top) / 2;

      if (dragY >= currentLine.bottom && dragY <= nextLine.top) {
        final insertionY = editorGlobalPosition.dy + gapCenter;
        return _InsertionResult(
            insertionY, _getDocumentOffsetForLineIndex(i + 1));
      }

      if (dragY >= currentLine.top && dragY <= currentLine.bottom) {
        final distanceToTopGap = i > 0
            ? (dragY - (lineInfos[i - 1].bottom + currentLine.top) / 2).abs()
            : double.infinity;
        final distanceToBottomGap = (dragY - gapCenter).abs();

        if (distanceToTopGap < distanceToBottomGap && i > 0) {
          final topGapCenter = (lineInfos[i - 1].bottom + currentLine.top) / 2;
          final insertionY = editorGlobalPosition.dy + topGapCenter;
          return _InsertionResult(
              insertionY, _getDocumentOffsetForLineIndex(i));
        } else {
          final insertionY = editorGlobalPosition.dy + gapCenter;
          return _InsertionResult(
              insertionY, _getDocumentOffsetForLineIndex(i + 1));
        }
      }
    }

    return _InsertionResult(globalDragPosition.dy,
        _getDocumentOffsetForLineIndex(lineInfos.length));
  }

  /// 根据行索引获取文档偏移量
  int _getDocumentOffsetForLineIndex(int lineIndex) {
    try {
      final document = widget.controller.document;
      int currentLineIndex = 0;
      int documentOffset = 0;

      for (final node in document.root.children) {
        if (node is Line) {
          if (currentLineIndex == lineIndex) return documentOffset;
          currentLineIndex++;
          documentOffset += node.length;
        } else if (node is Block) {
          for (final line in node.children.cast<Line>()) {
            if (currentLineIndex == lineIndex) return documentOffset;
            currentLineIndex++;
            documentOffset += line.length;
          }
        }
      }
      return document.length;
    } catch (e) {
      return widget.controller.document.length;
    }
  }

  /// 构建拖拽预览组件
  Widget _buildDragPreview(String textContent) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        textContent.trim().isEmpty ? '空行' : textContent.trim(),
        style: const TextStyle(fontSize: 14, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
