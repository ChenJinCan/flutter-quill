import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../controller/quill_controller.dart';
import '../../../document/nodes/block.dart';
import '../../../document/nodes/line.dart';
import 'swipe_manager.dart';

// 调试配置
const bool _kDebugDragSort = false; // 可以通过这个开关控制调试输出

void _debugPrint(String message) {
  if (_kDebugDragSort) {
    debugPrint(message);
  }
}

/// 用于存储TextLine位置信息的辅助类
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

/// 用于存储插入位置结果的辅助类
class _InsertionResult {
  _InsertionResult(
    this.insertionY,
    this.documentOffset,
  );
  final double insertionY;
  final int documentOffset;
}

/// 拖拽排序覆盖层 - 精简版本，模仿 Notion/Craft 交互
class DragSortOverlay {
  static OverlayEntry? _overlayEntry;
  static SwipeableComponent? _draggingComponent;
  static QuillController? _controller;
  static ScrollController? _scrollController;
  static BuildContext? _context;

  // 边缘滚动相关 - 智能方向检测版本
  static Timer? _scrollTimer;
  static bool _isAutoScrolling = false; // 是否正在自动滚动
  static const double _edgeZone = 60; // 边缘检测区域 - 减小到60px
  static const double _baseScrollSpeed = 800; // 基础滚动速度（像素/秒）
  static const double _maxScrollSpeed = 3000; // 最大滚动速度（像素/秒）
  static double _currentScrollVelocity = 0; // 当前滚动速度
  static int _lastScrollDirection = 0; // 上次滚动方向（-1向上，1向下，0无）

  // 当前拖拽位置
  static Offset? _currentPosition;

  // 拖拽插入位置（文档偏移量）
  static int? _insertionOffset;

  // 编辑器Key，用于获取正确的RenderBox
  static GlobalKey? _editorKey;

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
      _debugPrint('DragSortOverlay.show: 有其他组件在滑动，不显示拖拽覆盖层');
      return;
    }

    hide(); // 确保之前的覆盖层被移除
    _resetScrollState(); // 重置滚动状态

    _draggingComponent = component;
    _controller = controller;
    _scrollController = scrollController;
    _currentPosition = initialGlobalPosition;
    _context = context;
    _insertionOffset = null;
    _editorKey = editorKey;

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
    _stopAutoScroll();
    _overlayEntry?.remove();
    _overlayEntry = null;
    _draggingComponent = null;
    _controller = null;
    _scrollController = null;
    _currentPosition = null;
    _context = null;
    _insertionOffset = null;
    _editorKey = null;
  }

  /// 在焦点聚焦时隐藏覆盖层（由SwipeStateManager调用）
  static void hideOnFocus() {
    if (isVisible) {
      _debugPrint('DragSortOverlay.hideOnFocus: 编辑器获得焦点，隐藏拖拽覆盖层');
      hide();
    }
  }

  /// 更新拖拽位置 - 重新设计的核心逻辑
  static void updatePosition(Offset globalPosition) {
    _currentPosition = globalPosition;
    _handleEdgeScrolling(globalPosition);
    _overlayEntry?.markNeedsBuild();
    _debugPrint(
        'DragSortOverlay.updatePosition: 覆盖层位置更新 $globalPosition, 覆盖层可见: ${_overlayEntry != null}');
  }

  /// 获取滚动能力（合并逻辑）
  static (bool, bool) _getScrollCapabilities() {
    bool canScrollUp = false;
    bool canScrollDown = false;

    if (_editorKey != null) {
      try {
        // 通过editorKey获取QuillEditor的RenderBox
        final renderObject = _editorKey!.currentContext?.findRenderObject();
        if (renderObject is RenderBox) {
          final editorRenderBox = renderObject;
          final editorGlobalPosition =
              editorRenderBox.localToGlobal(Offset.zero);
          final editorSize = editorRenderBox.size;

          final editorTop = editorGlobalPosition.dy;
          final editorBottom = editorGlobalPosition.dy + editorSize.height;

          // 检查编辑器内容是否还能滚动
          final currentOffset = _scrollController!.offset;
          final maxOffset = _scrollController!.position.maxScrollExtent;

          canScrollUp = currentOffset > 0;
          canScrollDown = currentOffset < maxOffset;

          _debugPrint(
              '编辑器边界: 顶部=$editorTop, 底部=$editorBottom, 高度=${editorSize.height}');
          _debugPrint('滚动状态: 当前位置=$currentOffset, 最大位置=$maxOffset');
          _debugPrint('滚动能力: 可向上=$canScrollUp, 可向下=$canScrollDown');
        }
      } catch (e) {
        _debugPrint('获取编辑器边界失败: $e');
        // 如果无法获取编辑器边界，回退到基本的滚动检查
        final currentOffset = _scrollController!.offset;
        final maxOffset = _scrollController!.position.maxScrollExtent;
        canScrollUp = currentOffset > 0;
        canScrollDown = currentOffset < maxOffset;
      }
    }

    return (canScrollUp, canScrollDown);
  }

  /// 处理边缘滚动 - 屏幕边缘触发，编辑器边界限制
  static void _handleEdgeScrolling(Offset position) {
    if (_scrollController == null ||
        !_scrollController!.hasClients ||
        _context == null) {
      return;
    }

    // 1. 计算屏幕边缘距离
    final mediaQuery = MediaQuery.of(_context!);
    final effectiveTop = mediaQuery.padding.top + _getAppBarHeight();
    final effectiveBottom = mediaQuery.size.height;

    final distanceFromScreenTop = position.dy - effectiveTop;
    final distanceFromScreenBottom = effectiveBottom - position.dy;

    // 检查是否在屏幕边缘区域
    final inScreenTopEdge =
        distanceFromScreenTop >= 0 && distanceFromScreenTop < _edgeZone;
    final inScreenBottomEdge =
        distanceFromScreenBottom >= 0 && distanceFromScreenBottom < _edgeZone;

    // 2. 获取滚动能力（合并逻辑）
    final (canScrollUp, canScrollDown) = _getScrollCapabilities();

    _debugPrint(
        '屏幕边缘检测: 顶部距离=$distanceFromScreenTop, 底部距离=$distanceFromScreenBottom');
    _debugPrint('屏幕边缘状态: 顶部边缘=$inScreenTopEdge, 底部边缘=$inScreenBottomEdge');

    // 3. 处理滚动逻辑
    if (inScreenTopEdge || inScreenBottomEdge) {
      final desiredDirection = inScreenTopEdge ? -1 : 1;
      final distance =
          inScreenTopEdge ? distanceFromScreenTop : distanceFromScreenBottom;

      // 计算滚动速度
      final speedRatio = 1.0 - (distance / _edgeZone);
      _currentScrollVelocity = desiredDirection *
          (_baseScrollSpeed +
              (_maxScrollSpeed - _baseScrollSpeed) * speedRatio);
      _lastScrollDirection = desiredDirection;

      _startAutoScroll();
      _debugPrint('边缘滚动: 方向=$desiredDirection, 速度=$_currentScrollVelocity');
    } else if (!_isAutoScrolling) {
      _debugPrint('不在边缘区域且未在滚动');
    }
    // 如果正在滚动但不在边缘，让滚动自然停止
  }

  /// 完成拖拽排序操作
  static void completeDragSort() {
    _debugPrint('DragSortOverlay.completeDragSort: 开始检查参数');
    _debugPrint('  _draggingComponent: ${_draggingComponent?.componentId}');
    _debugPrint('  _controller: ${_controller != null}');
    _debugPrint('  _insertionOffset: $_insertionOffset');

    if (_draggingComponent == null ||
        _controller == null ||
        _insertionOffset == null) {
      _debugPrint('DragSortOverlay.completeDragSort: 缺少必要参数');
      hide();
      return;
    }

    try {
      _performDocumentReorder(
          _draggingComponent!, _controller!, _insertionOffset!);
    } catch (e) {
      _debugPrint('DragSortOverlay.completeDragSort: 拖拽排序失败: $e');
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
      _debugPrint('DragSortOverlay._performDocumentReorder: 插入位置在原位置范围内，无需移动');
      return;
    }

    _debugPrint('DragSortOverlay._performDocumentReorder: 开始重排序');
    _debugPrint('  源位置: $sourceOffset, 长度: $sourceLength');
    _debugPrint('  目标位置: $insertionOffset');

    // Step 1: 提取完整的 TextLine Delta（包含所有格式和属性）
    final completeLineDelta = controller.document
        .toDelta()
        .slice(sourceOffset, sourceOffset + sourceLength);

    final textContent =
        controller.document.getPlainText(sourceOffset, sourceLength);
    _debugPrint('  移动的文本: "${textContent.trim()}"');

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

      _debugPrint('  调整后的插入位置: $adjustedInsertionOffset');

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

    _debugPrint(
        'DragSortOverlay._performDocumentReorder: 重排序完成，插入位置: $adjustedInsertionOffset');
  }

  /// 获取准确的AppBar高度
  static double _getAppBarHeight() {
    if (_context == null) return 56;

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

    return 56; // 默认AppBar高度
  }

  /// 开始自动滚动 - 修复跳转问题的稳定版本
  static void _startAutoScroll() {
    if (_isAutoScrolling) return; // 避免重复启动

    _isAutoScrolling = true;
    // 降低帧率到60fps，避免过于频繁的更新导致跳转
    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      if (_scrollController == null || !_scrollController!.hasClients) {
        _stopAutoScroll();
        return;
      }

      final currentOffset = _scrollController!.offset;
      final maxOffset = _scrollController!.position.maxScrollExtent;

      // 检查是否已经到达编辑器边界
      if ((_currentScrollVelocity < 0 && currentOffset <= 0) ||
          (_currentScrollVelocity > 0 && currentOffset >= maxOffset)) {
        _debugPrint(
            '到达编辑器边界，停止滚动: 当前位置=$currentOffset, 最大位置=$maxOffset, 滚动方向=${_currentScrollVelocity < 0 ? "向上" : "向下"}');
        _stopAutoScroll();
        return;
      }

      // 计算新的滚动位置 - 使用稳定的时间步长
      final deltaTime = 0.016; // 16ms
      final scrollDelta = _currentScrollVelocity * deltaTime;

      // 限制单次滚动距离，避免大幅跳跃
      final maxSingleScroll = 20.0; // 单次最大滚动距离
      final clampedDelta = scrollDelta.clamp(-maxSingleScroll, maxSingleScroll);

      double newOffset = currentOffset + clampedDelta;

      // 严格的边界限制
      if (newOffset < 0) {
        newOffset = 0;
      } else if (newOffset > maxOffset) {
        newOffset = maxOffset;
      }

      // 使用安全的滚动方法
      if (!_safeScrollTo(newOffset)) {
        // 如果滚动失败，停止自动滚动
        _debugPrint('滚动失败，停止自动滚动: 目标位置=$newOffset, 当前位置=$currentOffset');
        _stopAutoScroll();
      }
    });
  }

  /// 停止自动滚动
  static void _stopAutoScroll() {
    _isAutoScrolling = false;
    _currentScrollVelocity = 0;
    _lastScrollDirection = 0;
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  /// 重置滚动状态 - 复用_stopAutoScroll逻辑
  static void _resetScrollState() {
    _stopAutoScroll();
  }

  /// 安全的滚动位置更新
  static bool _safeScrollTo(double targetOffset) {
    if (_scrollController == null || !_scrollController!.hasClients) {
      _debugPrint('_safeScrollTo失败: ScrollController为null或无客户端');
      return false;
    }

    try {
      final currentOffset = _scrollController!.offset;
      final maxOffset = _scrollController!.position.maxScrollExtent;

      // 限制目标位置在有效范围内
      double clampedOffset = targetOffset.clamp(0.0, maxOffset);

      // 检查是否有意义的移动（避免微小的抖动）
      if ((clampedOffset - currentOffset).abs() < 0.1) {
        _debugPrint(
            '_safeScrollTo: 移动距离太小，跳过滚动 (${(clampedOffset - currentOffset).abs()})');
        return true;
      }

      _scrollController!.jumpTo(clampedOffset);
      _debugPrint('_safeScrollTo成功: 从$currentOffset滚动到$clampedOffset');
      return true;
    } catch (e) {
      _debugPrint('_safeScrollTo异常: $e');
      return false;
    }
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

  /// 滚动位置改变时立即更新 - 强制同步
  void _onScrollChanged() {
    final currentScrollOffset = widget.scrollController?.offset;
    if (currentScrollOffset != _lastScrollOffset) {
      // 强制清除所有缓存
      _cachedLineInfos = null;
      _lastScrollOffset = currentScrollOffset;

      // 强制立即重建UI，确保位置指示器同步
      if (DragSortOverlay._currentPosition != null && mounted) {
        setState(() {
          // 强制重建，确保位置计算基于最新的滚动位置
        });
      }
    }
  }

  /// 获取LineInfo - 实时计算，不依赖缓存
  List<_LineInfo> _getLineInfos(RenderBox editorRenderBox) {
    // 每次都重新计算，确保位置准确
    final lineInfos = <_LineInfo>[];
    _collectTextLineInfos(editorRenderBox, Offset.zero, lineInfos);

    // 按Y位置排序
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

  /// 更新插入指示器位置 - 实时精确跟随
  void _updateInsertIndicator(Offset globalPosition) {
    final renderObject = widget.editorKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) {
      return;
    }

    try {
      final editorGlobalPosition = renderObject.localToGlobal(Offset.zero);
      final editorLocalPosition = renderObject.globalToLocal(globalPosition);
      final editorSize = renderObject.size;

      // 强制刷新LineInfo，确保获取最新位置
      _cachedLineInfos = null;
      final lineInfos = _getLineInfos(renderObject);

      // 智能边缘处理和精确跟随
      _InsertionResult? result;

      if (editorLocalPosition.dy < -50) {
        // 拖拽到编辑器上方较远位置，插入到顶部
        result = _InsertionResult(globalPosition.dy, 0);
      } else if (editorLocalPosition.dy > editorSize.height + 50) {
        // 拖拽到编辑器下方较远位置，插入到底部
        final documentLength = widget.controller.document.length;
        result = _InsertionResult(globalPosition.dy, documentLength);
      } else {
        // 在编辑器附近，精确计算插入位置
        result = _findBestInsertionPosition(lineInfos, editorLocalPosition.dy,
            editorGlobalPosition, globalPosition);
      }

      // 更新位置并触发重建
      if (result != null) {
        if (mounted) {
          setState(() {
            _insertIndicatorPosition = Offset(0, result!.insertionY);
          });
        }
        DragSortOverlay._insertionOffset = result!.documentOffset;
        _debugPrint(
            '位置指示器更新: ${result!.insertionY}, 文档偏移: ${result!.documentOffset}');
      } else {
        if (mounted) {
          setState(() {
            _insertIndicatorPosition = null;
          });
        }
        DragSortOverlay._insertionOffset = null;
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _insertIndicatorPosition = null;
        });
      }
      DragSortOverlay._insertionOffset = null;
      _debugPrint('位置指示器更新失败: $e');
    }
  }

  /// 找到最佳插入位置 - 精确同步跟随
  _InsertionResult? _findBestInsertionPosition(List<_LineInfo> lineInfos,
      double dragY, Offset editorGlobalPosition, Offset globalDragPosition) {
    if (lineInfos.isEmpty) {
      // 没有行时，指示器跟随拖拽位置
      return _InsertionResult(globalDragPosition.dy, 0);
    }

    const insertionMargin = 15.0;

    // 在第一行之前
    if (dragY < lineInfos.first.top + insertionMargin) {
      final insertionY = editorGlobalPosition.dy + lineInfos.first.top - 5;
      final documentOffset = _getDocumentOffsetForLineIndex(0);
      return _InsertionResult(insertionY, documentOffset);
    }

    // 在最后一行之后 - 指示器精确跟随全局拖拽位置
    if (dragY > lineInfos.last.bottom - insertionMargin) {
      // 直接使用全局拖拽位置，确保完全同步
      final documentOffset = _getDocumentOffsetForLineIndex(lineInfos.length);
      return _InsertionResult(globalDragPosition.dy, documentOffset);
    }

    // 在TextLine之间找最合适的位置
    for (int i = 0; i < lineInfos.length - 1; i++) {
      final currentLine = lineInfos[i];
      final nextLine = lineInfos[i + 1];

      final gapTop = currentLine.bottom;
      final gapBottom = nextLine.top;
      final gapCenter = (gapTop + gapBottom) / 2;

      // 拖拽位置在间隙中 - 使用间隙中心位置
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

    // 默认插入到末尾 - 指示器跟随全局拖拽位置
    final documentOffset = _getDocumentOffsetForLineIndex(lineInfos.length);
    return _InsertionResult(globalDragPosition.dy, documentOffset);
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
      _debugPrint('_getDocumentOffsetForLineIndex error: $e');
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
