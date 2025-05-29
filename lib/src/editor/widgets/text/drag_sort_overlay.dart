import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../controller/quill_controller.dart';
import '../../../document/document.dart';
import '../../../document/nodes/line.dart';
import '../../../document/nodes/block.dart';
import '../../../document/nodes/node.dart';
import 'swipe_manager.dart';

/// 拖拽排序覆盖层
/// 用于显示拖拽中的视觉反馈并处理拖拽排序逻辑
class DragSortOverlay {
  static OverlayEntry? _overlayEntry;
  static SwipeableComponent? _draggingComponent;
  static QuillController? _controller;
  static GlobalKey? _editorKey;
  static Offset? _initialPosition;
  static Size? _componentSize;
  static Widget? _dragPreview;

  /// 显示拖拽覆盖层
  static void show({
    required BuildContext context,
    required SwipeableComponent component,
    required QuillController controller,
    required GlobalKey editorKey,
    required Offset initialGlobalPosition,
  }) {
    hide(); // 确保之前的覆盖层被移除

    _draggingComponent = component;
    _controller = controller;
    _editorKey = editorKey;
    _initialPosition = initialGlobalPosition;

    // 创建拖拽预览
    _dragPreview = _createDragPreview(component);

    _overlayEntry = OverlayEntry(
      builder: (context) => _DragSortOverlayWidget(
        component: component,
        controller: controller,
        editorKey: editorKey,
        initialPosition: initialGlobalPosition,
        dragPreview: _dragPreview!,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 隐藏拖拽覆盖层
  static void hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _draggingComponent = null;
    _controller = null;
    _editorKey = null;
    _initialPosition = null;
    _componentSize = null;
    _dragPreview = null;
  }

  /// 更新拖拽位置
  static void updatePosition(Offset globalPosition) {
    if (_overlayEntry != null) {
      // 更新当前位置到静态变量，供覆盖层使用
      _currentDragPosition = globalPosition;

      // 处理拖拽更新
      _handleDragUpdate(globalPosition);

      // 重新构建覆盖层
      _overlayEntry!.markNeedsBuild();
    }
  }

  /// 创建拖拽预览组件
  static Widget _createDragPreview(SwipeableComponent component) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 300),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.drag_handle,
            color: Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              component.textContent.trim().isEmpty
                  ? '空行'
                  : component.textContent.trim(),
              style: const TextStyle(
                fontSize: 14,
                color: Colors.black87,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// 处理拖拽更新
  static void _handleDragUpdate(Offset globalPosition) {
    if (_controller == null || _draggingComponent == null) return;

    // 检测拖拽目标并显示插入位置指示器
    _detectDropTarget(globalPosition);
  }

  /// 处理拖拽结束
  static void _handleDragEnd(Offset globalPosition) {
    if (_controller == null || _draggingComponent == null) return;

    // 执行实际的文档重排序操作
    _performDocumentReorder(globalPosition);

    hide();
  }

  /// 检测拖拽目标
  static void _detectDropTarget(Offset globalPosition) {
    if (_controller == null || _editorKey == null) return;

    try {
      // 获取编辑器的RenderObject
      final renderObject = _editorKey!.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return;

      // 将全局坐标转换为编辑器内的局部坐标
      final localPosition = renderObject.globalToLocal(globalPosition);

      debugPrint('检测拖拽目标位置: global=$globalPosition, local=$localPosition');

      // 这里可以实现检测拖拽位置下方的组件
      // 并显示插入位置的指示器
      // 暂时使用简单的Y坐标比较来确定插入位置
    } catch (e) {
      debugPrint('检测拖拽目标失败: $e');
    }
  }

  /// 执行文档重排序
  static void _performDocumentReorder(Offset globalPosition) {
    if (_controller == null || _draggingComponent == null) return;

    try {
      // 获取拖拽组件的信息
      final draggingNode = _draggingComponent!.documentNode;
      final draggingOffset = _draggingComponent!.documentOffset;
      final draggingLength = _draggingComponent!.documentLength;

      // 在这里实现具体的重排序逻辑
      // 1. 找到目标插入位置
      final targetOffset = _findTargetOffset(globalPosition);

      if (targetOffset != null && targetOffset != draggingOffset) {
        // 2. 执行文档操作
        _reorderDocumentNode(
            draggingNode, draggingOffset, draggingLength, targetOffset);
      }
    } catch (e) {
      debugPrint('拖拽排序失败: $e');
    }
  }

  /// 找到目标插入位置
  static int? _findTargetOffset(Offset globalPosition) {
    if (_controller == null || _draggingComponent == null || _editorKey == null)
      return null;

    try {
      // 获取编辑器的RenderObject
      final renderObject = _editorKey!.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) return null;

      // 将全局坐标转换为编辑器内的局部坐标
      final localPosition = renderObject.globalToLocal(globalPosition);

      // 获取文档总长度
      final documentLength = _controller!.document.length;
      final draggingOffset = _draggingComponent!.documentOffset;
      final draggingLength = _draggingComponent!.documentLength;

      // 简单实现：根据Y坐标的比例计算目标位置
      // 这是一个简化的实现，实际项目中可能需要更精确的位置计算
      final editorHeight = renderObject.size.height;
      final relativeY = localPosition.dy / editorHeight;

      // 计算目标位置（相对于文档的比例）
      int targetOffset = (relativeY * documentLength).round();

      // 确保目标位置在有效范围内
      targetOffset = targetOffset.clamp(0, documentLength);

      // 如果目标位置与拖拽位置太接近，则不移动
      if ((targetOffset - draggingOffset).abs() < draggingLength) {
        return null;
      }

      debugPrint(
          '计算目标位置: $targetOffset (拖拽位置: $draggingOffset, 文档长度: $documentLength)');
      return targetOffset;
    } catch (e) {
      debugPrint('计算目标位置失败: $e');
      return null;
    }
  }

  /// 重排序文档节点
  static void _reorderDocumentNode(
    Node draggingNode,
    int fromOffset,
    int length,
    int toOffset,
  ) {
    if (_controller == null) return;

    // 获取要移动的文本内容
    final text = _controller!.document
        .toPlainText()
        .substring(fromOffset, fromOffset + length);

    // 删除原位置的内容
    _controller!.document.delete(fromOffset, length);

    // 调整目标位置（如果目标位置在删除位置之后）
    int adjustedToOffset = toOffset;
    if (toOffset > fromOffset) {
      adjustedToOffset = toOffset - length;
    }

    // 在新位置插入内容
    _controller!.document.insert(adjustedToOffset, text);

    // 更新选择位置到新的位置
    _controller!.updateSelection(
      TextSelection.collapsed(offset: adjustedToOffset),
      ChangeSource.local,
    );
  }

  // 添加静态变量来跟踪当前拖拽位置
  static Offset? _currentDragPosition;
}

/// 拖拽排序覆盖层组件
class _DragSortOverlayWidget extends StatefulWidget {
  const _DragSortOverlayWidget({
    required this.component,
    required this.controller,
    required this.editorKey,
    required this.initialPosition,
    required this.dragPreview,
  });

  final SwipeableComponent component;
  final QuillController controller;
  final GlobalKey editorKey;
  final Offset initialPosition;
  final Widget dragPreview;

  @override
  State<_DragSortOverlayWidget> createState() => _DragSortOverlayWidgetState();
}

class _DragSortOverlayWidgetState extends State<_DragSortOverlayWidget> {
  Offset _currentPosition = Offset.zero;
  bool _isDragging = false;

  // 插入位置指示器相关
  Offset? _insertionIndicatorPosition;
  bool _showInsertionIndicator = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.initialPosition;
    _isDragging = true; // 覆盖层显示时就是拖拽状态
  }

  /// 更新插入位置指示器
  void _updateInsertionIndicator(Offset globalPosition) {
    debugPrint(
        '🔴 _updateInsertionIndicator 被调用: $globalPosition, mounted=$mounted');

    if (!mounted) return;

    try {
      debugPrint('🔴 开始处理插入指示器逻辑...');

      // 获取编辑器的RenderObject
      final renderObject = widget.editorKey.currentContext?.findRenderObject();
      if (renderObject is! RenderBox) {
        debugPrint('🔴 无法获取 RenderBox');
        return;
      }

      // 将全局坐标转换为编辑器内的局部坐标
      final editorLocalPosition = renderObject.globalToLocal(globalPosition);
      final editorGlobalPosition = renderObject.localToGlobal(Offset.zero);

      // 获取编辑器尺寸
      final editorSize = renderObject.size;

      debugPrint('🔴 编辑器信息: 局部位置=$editorLocalPosition, 尺寸=$editorSize');

      // 确保拖拽位置在编辑器范围内
      if (editorLocalPosition.dy < 0 ||
          editorLocalPosition.dy > editorSize.height) {
        debugPrint('🔴 拖拽位置在编辑器范围外，隐藏指示器');
        setState(() {
          _showInsertionIndicator = false;
        });
        return;
      }

      // 计算相对位置（0.0 到 1.0）
      final relativeY =
          (editorLocalPosition.dy / editorSize.height).clamp(0.0, 1.0);

      // 基于文档行数估算插入位置
      final doc = widget.controller.document;
      final totalLines = doc.root.children.length;

      // 计算目标行索引
      int targetLineIndex = (relativeY * totalLines).floor();
      targetLineIndex = targetLineIndex.clamp(0, totalLines);

      // 计算指示器的Y位置
      double indicatorY;
      if (targetLineIndex == 0) {
        // 插入到第一行之前
        indicatorY = editorGlobalPosition.dy + 10;
      } else if (targetLineIndex >= totalLines) {
        // 插入到最后一行之后
        indicatorY = editorGlobalPosition.dy + editorSize.height - 10;
      } else {
        // 插入到行与行之间
        final lineProgress = relativeY * totalLines - targetLineIndex;
        final baseY = editorGlobalPosition.dy +
            (targetLineIndex / totalLines) * editorSize.height;
        final lineHeight = editorSize.height / totalLines;
        indicatorY = baseY + lineHeight * lineProgress;
      }

      debugPrint('🔴 计算结果: 目标行=$targetLineIndex/$totalLines, 指示器Y=$indicatorY');
      debugPrint(
          '🔴 设置指示器位置: Offset(${editorGlobalPosition.dx + 20}, $indicatorY)');

      setState(() {
        _insertionIndicatorPosition =
            Offset(editorGlobalPosition.dx + 20, indicatorY);
        _showInsertionIndicator = true;
      });

      debugPrint(
          '🔴 setState完成: _showInsertionIndicator=$_showInsertionIndicator');
      debugPrint('智能插入指示器: 目标行=$targetLineIndex/$totalLines, Y=$indicatorY');
    } catch (e) {
      debugPrint('🔴 更新插入指示器失败: $e');
      setState(() {
        _showInsertionIndicator = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('🟦 覆盖层 build 被调用');

    // 从静态变量获取当前拖拽位置
    if (DragSortOverlay._currentDragPosition != null) {
      _currentPosition = DragSortOverlay._currentDragPosition!;
      debugPrint('🟦 更新当前位置: $_currentPosition');

      // 更新插入位置指示器
      _updateInsertionIndicator(_currentPosition);
    }

    debugPrint(
        '🟦 构建覆盖层: showInsertionIndicator=$_showInsertionIndicator, position=$_insertionIndicatorPosition');

    return Positioned.fill(
      child: Stack(
        children: [
          // 半透明背景 - 不拦截手势
          IgnorePointer(
            child: Container(
              color: Colors.black.withOpacity(0.1),
            ),
          ),

          // 插入位置指示器 - 不拦截手势
          if (_showInsertionIndicator &&
              _insertionIndicatorPosition != null) ...[
            IgnorePointer(child: _buildInsertionIndicator()),
            // 添加一个显眼的调试指示器
            IgnorePointer(
              child: Positioned(
                left: 0,
                top: _insertionIndicatorPosition!.dy,
                child: Container(
                  width: 50,
                  height: 10,
                  color: Colors.red,
                  child: const Text('HERE',
                      style: TextStyle(color: Colors.white, fontSize: 8)),
                ),
              ),
            ),
          ],

          // 拖拽预览 - 不拦截手势
          Positioned(
            left: _currentPosition.dx - 150, // 预览组件宽度的一半
            top: _currentPosition.dy - 20, // 预览组件高度的一半
            child: IgnorePointer(
              child: Transform.scale(
                scale: _isDragging ? 1.05 : 1.0,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  child: widget.dragPreview,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建插入位置指示器
  Widget _buildInsertionIndicator() {
    if (_insertionIndicatorPosition == null) return const SizedBox.shrink();

    return Positioned(
      left: _insertionIndicatorPosition!.dx,
      right: 20, // 添加right约束以支持Expanded
      top: _insertionIndicatorPosition!.dy - 3, // 指示器线条的一半高度
      child: SizedBox(
        width: MediaQuery.of(context).size.width - 20,
        child: Container(
          height: 3,
          margin: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF2196F3),
            borderRadius: BorderRadius.circular(1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2196F3).withOpacity(0.3),
                blurRadius: 4,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
