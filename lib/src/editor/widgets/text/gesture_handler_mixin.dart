import 'dart:async';
import 'package:flutter/rendering.dart';

import 'swipe_manager.dart';

/// 手势处理配置类
class GestureConfig {
  const GestureConfig({
    this.enableSwipe = true,
    this.enableLongPress = true,
    this.enableDrag = true,
    this.swipeThreshold = 40, // 降低从60到40
    this.moveThreshold = 10, // 降低从15到10
    this.horizontalToVerticalRatio = 1.5, // 降低从2到1.5
    this.consistentDirectionSamples = 2, // 降低从3到2
    this.longPressDuration = const Duration(milliseconds: 700),
    this.maxSwipeOffset = 40,
  });

  /// 是否启用滑动手势
  final bool enableSwipe;

  /// 是否启用长按手势
  final bool enableLongPress;

  /// 是否启用拖拽手势
  final bool enableDrag;

  /// 滑动阈值
  final double swipeThreshold;

  /// 移动阈值
  final double moveThreshold;

  /// 水平垂直移动比例
  final double horizontalToVerticalRatio;

  /// 连续方向采样数
  final int consistentDirectionSamples;

  /// 长按持续时间
  final Duration longPressDuration;

  /// 最大滑动偏移
  final double maxSwipeOffset;
}

/// 手势处理混入类
/// 提供滑动、长按、拖拽等手势的通用逻辑
mixin GestureHandlerMixin on RenderBox implements SwipeableComponent {
  /// 手势配置
  GestureConfig get gestureConfig => const GestureConfig();

  /// 是否有焦点
  bool get hasFocus;

  /// 滑动状态管理器
  final SwipeStateManager _swipeManager = SwipeStateManager();

  // 滑动状态
  bool _isSwipingLeft = false;
  bool _isSwipingRight = false;
  double _swipeOffset = 0;

  // 拖拽状态
  bool _isLongPressing = false;
  bool _isDragging = false;
  Timer? _longPressTimer;

  // 手势检测状态
  Offset? _dragStartPosition;
  final List<double> _horizontalMovements = [];

  // 选中状态
  bool _isSelected = false;

  // 回调函数
  VoidCallback? _onSwipeLeft;
  VoidCallback? _onSwipeRight;
  VoidCallback? _onLongPressStart;
  VoidCallback? _onDragEnd;

  /// 设置滑动回调
  void setSwipeCallbacks({
    VoidCallback? onSwipeLeft,
    VoidCallback? onSwipeRight,
  }) {
    _onSwipeLeft = onSwipeLeft;
    _onSwipeRight = onSwipeRight;
  }

  /// 设置拖拽回调
  void setDragCallbacks({
    VoidCallback? onLongPressStart,
    VoidCallback? onDragEnd,
  }) {
    _onLongPressStart = onLongPressStart;
    _onDragEnd = onDragEnd;
  }

  /// 检查是否应该处理手势事件
  bool shouldHandleGestureEvent() {
    // 如果没有启用任何手势，直接返回
    if (!gestureConfig.enableSwipe &&
        !gestureConfig.enableLongPress &&
        !gestureConfig.enableDrag) {
      return false;
    }

    // 检查是否有光标显示在当前组件上
    final hasCursorOnThisComponent =
        hasFocus && shouldPreventGestureWhenHasCursor();

    // 在聚焦状态下的限制检查
    if (hasFocus) {
      // 聚焦时不允许滑动操作
      if (!gestureConfig.enableDrag) return false;

      // 如果当前组件有光标，禁用所有手势
      if (hasCursorOnThisComponent) {
        debugPrint('当前组件被选中且聚焦，禁用所有手势操作');
        return false;
      }
    }

    return true;
  }

  /// 子类可以重写此方法来自定义光标检测逻辑
  bool shouldPreventGestureWhenHasCursor() => false;

  /// 清除组件的选中状态（由SwipeStateManager调用）
  void clearSelectionState() {
    if (_isSelected) {
      _isSelected = false;
      markNeedsPaint();
    }
  }

  /// 检查是否正在滚动
  bool get _isScrolling {
    return _swipeManager.scrollController != null &&
        _swipeManager.scrollController!.hasClients &&
        _swipeManager.scrollController!.position.isScrollingNotifier.value;
  }

  /// 处理指针事件的通用逻辑
  ///
  /// 新的简化策略：
  /// 1. 每个组件独立处理自己的手势
  /// 2. 优先级：拖拽 > 滚动 > 滑动
  /// 3. 移除复杂的组件间冲突检查
  void handleGestureEvent(PointerEvent event, BoxHitTestEntry entry) {
    // 检查是否应该处理手势
    if (!shouldHandleGestureEvent()) {
      return;
    }

    // 如果当前组件正在拖拽，优先处理拖拽
    if (_isDragging) {
      if (event is PointerMoveEvent && _dragStartPosition != null) {
        _updateDragPosition(event.localPosition, event.position);
      } else if (event is PointerUpEvent && _dragStartPosition != null) {
        _handleDragEnd();
      }
      return;
    }

    // 如果当前组件正在滑动，优先处理滑动
    if (_isSwipingLeft || _isSwipingRight) {
      debugPrint('当前组件正在滑动，优先处理滑动事件');
      if (event is PointerMoveEvent && _dragStartPosition != null) {
        _handlePointerMove(event);
      } else if (event is PointerUpEvent && _dragStartPosition != null) {
        _handlePointerUp(event);
      } else if (event is PointerCancelEvent) {
        _handlePointerCancel();
      }
      return;
    }

    // 如果正在滚动，让滚动优先（除非已经在处理手势）
    if (_isScrolling && !_isLongPressing && !_isDragging) {
      if (_longPressTimer != null) {
        _cancelLongPressDetection();
        debugPrint('滚动优先，取消长按检测');
      }
      return;
    }

    // 处理新的手势事件
    if (event is PointerDownEvent) {
      _handlePointerDown(event);
    } else if (event is PointerMoveEvent && _dragStartPosition != null) {
      _handlePointerMove(event);
    } else if (event is PointerUpEvent && _dragStartPosition != null) {
      _handlePointerUp(event);
    } else if (event is PointerCancelEvent) {
      _handlePointerCancel();
    }
  }

  /// 处理按下事件
  void _handlePointerDown(PointerDownEvent event) {
    // 重置当前组件的状态
    _dragStartPosition = event.localPosition;
    _horizontalMovements.clear();

    debugPrint('PointerDown: 开始新的手势检测 ${event.localPosition}');

    // 如果当前组件有光标，禁用所有手势
    if (hasFocus && shouldPreventGestureWhenHasCursor()) {
      debugPrint('当前组件被选中且聚焦，不启动任何手势检测');
      return;
    }

    // 启动长按检测（用于拖拽）
    if (gestureConfig.enableLongPress && gestureConfig.enableDrag) {
      _startLongPressDetection(event.localPosition);
      debugPrint('开始长按检测: ${event.localPosition}');
    }
  }

  /// 处理移动事件
  void _handlePointerMove(PointerMoveEvent event) {
    final delta = event.localPosition - _dragStartPosition!;
    final horizontalDistance = delta.dx.abs();
    final verticalDistance = delta.dy.abs();

    debugPrint(
        'PointerMove: delta=$delta, horizontal=$horizontalDistance, vertical=$verticalDistance');

    // 如果正在滚动，取消长按检测（但不中断已经开始的拖拽）
    if (_isScrolling && !_isDragging && !_isLongPressing) {
      if (_longPressTimer != null) {
        _cancelLongPressDetection();
        debugPrint('移动中检测到滚动，取消长按检测');
      }
      return;
    }

    // 记录水平移动方向
    _recordHorizontalMovement(delta.dx, horizontalDistance);

    // 如果已经在拖拽，更新拖拽位置
    if (_isDragging) {
      _updateDragPosition(event.localPosition, event.position);
      return;
    }

    // 如果已经在长按状态，直接更新拖拽位置（优先级最高，不受滚动影响）
    if (_isLongPressing) {
      if (_isDragging) {
        // 已经在拖拽，直接更新位置
        _updateDragPosition(event.localPosition, event.position);
      } else {
        // 长按状态但还未开始拖拽，立即开始
        debugPrint('长按状态下开始移动，立即开始拖拽');
        _startDragging(event.localPosition);
        if (_isDragging) {
          _updateDragPosition(event.localPosition, event.position);
        }
      }
      return;
    }

    // 简化的滑动检测：只检查基本条件
    if (gestureConfig.enableSwipe &&
        !_isLongPressing &&
        !_isDragging &&
        !_isScrolling &&
        horizontalDistance > gestureConfig.moveThreshold &&
        verticalDistance < horizontalDistance &&
        !(_isSwipingLeft || _isSwipingRight)) {
      final direction =
          delta.dx < 0 ? SwipeDirection.left : SwipeDirection.right;

      // 检查是否有其他组件在滑动，如果有则阻止当前滑动
      if (_swipeManager.currentSwipingComponent != null &&
          _swipeManager.currentSwipingComponent != this) {
        debugPrint('其他组件正在滑动，阻止当前组件滑动');
        return;
      }

      // 通知SwipeStateManager开始滑动（用于互斥）
      if (_swipeManager.startSwipe(this, direction, horizontalDistance)) {
        // 设置本地滑动状态
        if (direction == SwipeDirection.left) {
          _isSwipingLeft = true;
          _isSwipingRight = false;
        } else {
          _isSwipingRight = true;
          _isSwipingLeft = false;
        }
        _swipeOffset =
            horizontalDistance.clamp(0.0, gestureConfig.maxSwipeOffset);
        markNeedsPaint();

        debugPrint('开始滑动: direction=$direction, distance=$horizontalDistance');
      } else {
        debugPrint('SwipeStateManager拒绝滑动');
      }
      return;
    }

    // 如果已经在滑动中，更新滑动偏移量
    if (_isSwipingLeft || _isSwipingRight) {
      final direction =
          delta.dx < 0 ? SwipeDirection.left : SwipeDirection.right;

      // 确保滑动方向一致
      if ((_isSwipingLeft && direction == SwipeDirection.left) ||
          (_isSwipingRight && direction == SwipeDirection.right)) {
        _swipeOffset =
            horizontalDistance.clamp(0.0, gestureConfig.maxSwipeOffset);
        markNeedsPaint();
        debugPrint('更新滑动偏移: direction=$direction, offset=$_swipeOffset');
      }
    }
  }

  /// 处理抬起事件
  void _handlePointerUp(PointerUpEvent event) {
    debugPrint(
        '抬起事件: isDragging=$_isDragging, isLongPressing=$_isLongPressing, isSwipingLeft=$_isSwipingLeft, isSwipingRight=$_isSwipingRight');

    // 如果正在拖拽，结束拖拽
    if (_isDragging) {
      _handleDragEnd();
      return;
    }

    // 处理滑动手势结束
    if (_isSwipingLeft || _isSwipingRight) {
      final delta = event.localPosition - _dragStartPosition!;
      final horizontalDistance = delta.dx.abs();
      final verticalDistance = delta.dy.abs();

      debugPrint(
          '滑动检查: horizontalDistance=$horizontalDistance, verticalDistance=$verticalDistance');

      // 简化的滑动完成判断
      if (horizontalDistance >= gestureConfig.swipeThreshold) {
        final direction =
            delta.dx < 0 ? SwipeDirection.left : SwipeDirection.right;

        debugPrint('滑动完成: direction=$direction, distance=$horizontalDistance');

        // 触发滑动回调
        if (!hasFocus) {
          if (direction == SwipeDirection.left) {
            _onSwipeLeft?.call();
            debugPrint('触发左滑回调');
          } else {
            _onSwipeRight?.call();
            debugPrint('触发右滑回调');
          }
        }

        // 设置选中状态
        _isSelected = true;
        debugPrint('设置组件为选中状态');

        // 调用SwipeStateManager的选中回调
        _swipeManager.selectComponent(this, direction);
        debugPrint('触发ComponentSelect回调');
      } else {
        debugPrint(
            '滑动距离不足，取消滑动 (需要距离>=${gestureConfig.swipeThreshold}, 当前:$horizontalDistance)');
      }

      // 重置滑动状态
      _isSwipingLeft = false;
      _isSwipingRight = false;
      _swipeOffset = 0.0;
      markNeedsPaint();
      debugPrint('重置滑动视觉偏移');
    }

    // 重置手势检测状态
    _resetGestureDetectionStates();
  }

  /// 记录水平移动方向
  void _recordHorizontalMovement(double deltaX, double horizontalDistance) {
    if (horizontalDistance > 5.0) {
      _horizontalMovements.add(deltaX);
      if (_horizontalMovements.length > 5) {
        _horizontalMovements.removeAt(0);
      }
    }
  }

  /// 开始长按检测
  void _startLongPressDetection(Offset position) {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(gestureConfig.longPressDuration, () {
      // 在长按定时器触发时再次检查是否有滚动发生
      if (_isScrolling) {
        debugPrint('长按定时器触发时检测到滚动，取消长按拖拽');
        return;
      }

      if (!_isLongPressing && !_isDragging) {
        if (!_swipeManager.shouldAllowDrag(this)) {
          debugPrint('长按检测: 当前组件不允许拖拽');
          return;
        }

        // 长按检测成功，立即开始拖拽并显示预览
        _isLongPressing = true;
        _onLongPressStart?.call();
        debugPrint('长按检测成功，立即开始拖拽');

        // 立即开始拖拽，显示预览
        _startDragging(position);
        markNeedsPaint();
      }
    });
  }

  /// 取消长按检测
  void _cancelLongPressDetection() {
    _longPressTimer?.cancel();
    _longPressTimer = null;
    if (_isLongPressing || _isDragging) {
      _isLongPressing = false;
      if (_isDragging) {
        _isDragging = false;
        _swipeManager.endDrag();
        // debugPrint('取消长按检测，结束拖拽状态');
      }
      _onDragEnd?.call();
      // debugPrint('取消长按检测，重置状态');
      markNeedsPaint();
    }
  }

  /// 开始拖拽
  void _startDragging(Offset position) {
    if (_isLongPressing && !_isDragging) {
      debugPrint('准备开始拖拽，调用 SwipeStateManager.startDrag');

      // 现在真正开始拖拽，调用 SwipeStateManager.startDrag
      final success = _swipeManager.startDrag(this);
      if (!success) {
        debugPrint('开始拖拽: SwipeStateManager拒绝拖拽');
        return;
      }

      _isDragging = true;
      final globalPosition = localToGlobal(position);
      debugPrint('开始拖拽成功，更新拖拽位置: $globalPosition');
      _swipeManager.updateDrag(globalPosition);
      markNeedsPaint();
      debugPrint('真正开始拖拽，现在会阻止其他手势');
    } else {
      debugPrint(
          '开始拖拽失败: isLongPressing=$_isLongPressing, isDragging=$_isDragging');
    }
  }

  /// 更新拖拽位置
  void _updateDragPosition(Offset localPosition,
      [Offset? screenGlobalPosition]) {
    if (_isDragging) {
      // 优先使用屏幕绝对坐标，如果没有则使用转换后的坐标
      final globalPosition =
          screenGlobalPosition ?? localToGlobal(localPosition);
      debugPrint('更新拖拽位置: local=$localPosition, global=$globalPosition');
      _swipeManager.updateDrag(globalPosition);
      markNeedsPaint();
    } else {
      debugPrint('尝试更新拖拽位置但未在拖拽状态: isDragging=$_isDragging');
    }
  }

  /// 重置手势状态
  void _resetGestureState() {
    _horizontalMovements.clear();
  }

  /// 处理拖拽结束
  void _handleDragEnd() {
    if (_isDragging) {
      _cancelLongPressDetection();
      debugPrint('拖拽结束');
    }
    _resetAllGestureStates();
  }

  /// 处理指针取消事件
  void _handlePointerCancel() {
    debugPrint('指针取消事件');
    _resetAllGestureStates();
  }

  /// 重置所有手势状态
  void _resetAllGestureStates() {
    _dragStartPosition = null;

    // 只清理当前组件相关的状态，避免影响其他组件
    if (_swipeManager.currentSwipingComponent == this) {
      debugPrint('重置当前组件的滑动状态');
      _swipeManager.endSwipe(this);
    }
    // 移除强制重置其他组件的逻辑，避免过度清理

    _cancelLongPressDetection();
    _resetGestureState();
    debugPrint('重置所有手势状态');
  }

  /// 重置手势检测状态（不影响滑动选中状态）
  void _resetGestureDetectionStates() {
    _dragStartPosition = null;
    _cancelLongPressDetection();
    _resetGestureState();
    debugPrint('重置手势检测状态');
  }

  /// 手势处理流程说明：
  /// PointerDown -> 开始长按检测（如果允许）
  /// PointerMove -> 检查优先级：滚动 > 拖拽 > 滑动
  /// PointerUp -> 根据当前状态结束相应手势并重置所有状态
  ///
  /// 处理按下事件

  // SwipeableComponent 接口实现

  @override
  bool performSwipe(SwipeDirection direction, double offset) {
    debugPrint(
        'performSwipe: direction=$direction, offset=$offset, 当前状态: isSwipingLeft=$_isSwipingLeft, isSwipingRight=$_isSwipingRight');

    switch (direction) {
      case SwipeDirection.left:
        if (!_isSwipingLeft) {
          _isSwipingLeft = true;
          _isSwipingRight = false;
          _swipeOffset = 0.0;
          debugPrint('performSwipe: 设置左滑状态');
        }
        _swipeOffset = offset.clamp(0.0, gestureConfig.maxSwipeOffset);
        markNeedsPaint();
        debugPrint('performSwipe: 左滑偏移更新为 $_swipeOffset');
        return true;
      case SwipeDirection.right:
        if (!_isSwipingRight) {
          _isSwipingRight = true;
          _isSwipingLeft = false;
          _swipeOffset = 0.0;
          debugPrint('performSwipe: 设置右滑状态');
        }
        _swipeOffset = offset.clamp(0.0, gestureConfig.maxSwipeOffset);
        markNeedsPaint();
        debugPrint('performSwipe: 右滑偏移更新为 $_swipeOffset');
        return true;
    }
  }

  @override
  void resetSwipe() {
    debugPrint(
        'resetSwipe: 重置前状态: isSwipingLeft=$_isSwipingLeft, isSwipingRight=$_isSwipingRight, swipeOffset=$_swipeOffset');
    _isSwipingLeft = false;
    _isSwipingRight = false;
    _swipeOffset = 0.0;
    markNeedsPaint();
    debugPrint('resetSwipe: 重置滑动视觉状态完成');
  }

  @override
  void endSwipe() {
    if (_swipeOffset > gestureConfig.maxSwipeOffset * 0.5) {
      if (_isSwipingLeft) {
        _onSwipeLeft?.call();
      } else if (_isSwipingRight) {
        _onSwipeRight?.call();
      }
    }
    resetSwipe();
    debugPrint('结束滑动');
  }

  @override
  void setSelected(bool selected) {
    if (_isSelected != selected) {
      _isSelected = selected;
      markNeedsPaint();
    }
  }

  @override
  bool startDrag() {
    if (_isLongPressing && !_isDragging) {
      _isDragging = true;
      markNeedsPaint();
      return true;
    }
    return false;
  }

  @override
  void endDrag() {
    _isDragging = false;
    _isLongPressing = false;
    _cancelLongPressDetection();
    _resetGestureState();
    _dragStartPosition = null;
    markNeedsPaint();
  }

  /// 获取滑动状态信息
  SwipeState get swipeState => SwipeState(
        isSwipingLeft: _isSwipingLeft,
        isSwipingRight: _isSwipingRight,
        swipeOffset: _swipeOffset,
        isDragging: _isDragging,
        isSelected: _isSelected,
      );

  /// 绘制滑动和选中效果的通用方法
  void paintSwipeEffects(PaintingContext context, Offset offset) {
    // 处理滑动效果
    var effectiveOffset = offset;
    if (!hasFocus) {
      if (_isSwipingLeft) {
        effectiveOffset = offset.translate(-_swipeOffset, 0);
      } else if (_isSwipingRight) {
        effectiveOffset = offset.translate(_swipeOffset, 0);
      }
    }

    // 绘制拖拽状态背景
    if (_isDragging) {
      final dragPaint = Paint()
        ..color = const Color(0xFF2196F3).withValues(alpha: 0.2);

      final dragRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          effectiveOffset.dx - 2.0,
          effectiveOffset.dy,
          size.width + 4.0,
          size.height,
        ),
        const Radius.circular(4),
      );
      context.canvas.drawRRect(dragRRect, dragPaint);
    }

    // 绘制选中状态背景
    if (_isSelected && !_isDragging) {
      final selectedPaint = Paint()
        ..color = const Color(0xFF2196F3).withValues(alpha: 0.2);
      final selectedRRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          effectiveOffset.dx - 2.0,
          effectiveOffset.dy,
          size.width + 4.0,
          size.height,
        ),
        const Radius.circular(4),
      );
      context.canvas.drawRRect(selectedRRect, selectedPaint);
    }

    // 绘制滑动指示器（仅在非拖拽状态下且非聚焦状态下显示）
    if ((_isSwipingLeft || _isSwipingRight) && !_isDragging && !hasFocus) {
      final indicatorColor = _isSwipingLeft
          ? const Color(0xFFF44336) // 红色
          : const Color(0xFF4CAF50); // 绿色
      final indicatorPaint = Paint()
        ..color = indicatorColor.withValues(alpha: 0.3);
      const indicatorWidth = 4.0;
      final indicatorRect = _isSwipingLeft
          ? Rect.fromLTWH(
              effectiveOffset.dx - indicatorWidth,
              effectiveOffset.dy,
              indicatorWidth,
              size.height,
            )
          : Rect.fromLTWH(
              effectiveOffset.dx + size.width,
              effectiveOffset.dy,
              indicatorWidth,
              size.height,
            );
      context.canvas.drawRect(indicatorRect, indicatorPaint);
    }

    // 返回有效偏移量供子类使用
    _lastEffectiveOffset = effectiveOffset;
  }

  Offset? _lastEffectiveOffset;
  Offset get effectiveOffset => _lastEffectiveOffset ?? Offset.zero;

  /// 获取当前是否正在向左滑动
  bool get isSwipingLeft => _isSwipingLeft;

  /// 获取当前是否正在向右滑动
  bool get isSwipingRight => _isSwipingRight;

  /// 检查是否处于长按状态
  bool get isLongPressing => _isLongPressing;
}

/// 滑动状态信息类
class SwipeState {
  const SwipeState({
    required this.isSwipingLeft,
    required this.isSwipingRight,
    required this.swipeOffset,
    required this.isDragging,
    required this.isSelected,
  });

  final bool isSwipingLeft;
  final bool isSwipingRight;
  final double swipeOffset;
  final bool isDragging;
  final bool isSelected;
}
