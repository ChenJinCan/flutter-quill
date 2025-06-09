import 'dart:async';
import 'dart:math';
import 'package:flutter/rendering.dart';

import 'swipe_manager.dart';

/// 手势处理配置类
class GestureConfig {
  const GestureConfig({
    this.enableSwipe = true,
    this.enableLongPress = true,
    this.enableDrag = true,
    this.swipeThreshold = 60,
    this.moveThreshold = 15,
    this.horizontalToVerticalRatio = 2,
    this.consistentDirectionSamples = 3,
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
  double _totalDragDistance = 0;
  final List<double> _horizontalMovements = [];
  int _consistentHorizontalCount = 0;

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

  /// 处理指针事件的通用逻辑
  void handleGestureEvent(PointerEvent event, BoxHitTestEntry entry) {
    // 检查是否应该处理手势
    if (!shouldHandleGestureEvent()) {
      return;
    }

    // 如果全局正在拖拽或滑动，但当前组件不是操作者，则消费事件避免滚动冲突
    // 但是要允许拖拽时的边缘滚动
    if (_swipeManager.shouldPreventOtherGestures() &&
        event is PointerMoveEvent &&
        !_isDragging &&
        !_isSwipingLeft &&
        !_isSwipingRight) {
      // 检查是否正在进行拖拽排序，如果是则允许滚动
      if (_swipeManager.isDragging) {
        // debugPrint('拖拽排序中，允许滚动事件通过');
        // 不return，让事件继续传递以支持边缘滚动
      } else {
        // 只有当前组件不是操作者时才消费事件
        debugPrint('阻止滚动，消费移动事件 - 其他组件正在操作');
        return;
      }
    }

    if (event is PointerDownEvent) {
      _handlePointerDown(event);
    } else if (event is PointerMoveEvent && _dragStartPosition != null) {
      _handlePointerMove(event);
    } else if (event is PointerUpEvent && _dragStartPosition != null) {
      _handlePointerUp(event);
    } else if (event is PointerCancelEvent) {
      // 处理指针取消事件，但不取消拖拽状态
    }
  }

  /// 处理按下事件
  void _handlePointerDown(PointerDownEvent event) {
    _dragStartPosition = event.localPosition;
    _totalDragDistance = 0.0;
    _horizontalMovements.clear();
    _consistentHorizontalCount = 0;

    // 在聚焦状态下的处理
    if (hasFocus) {
      final hasCursorOnThisComponent = shouldPreventGestureWhenHasCursor();
      if (hasCursorOnThisComponent) {
        debugPrint('当前组件被选中且聚焦，不启动任何手势检测');
        return;
      } else if (gestureConfig.enableLongPress && gestureConfig.enableDrag) {
        // 其他组件在聚焦状态下只允许长按拖动
        _startLongPressDetection(event.localPosition);
        debugPrint('其他组件在聚焦状态下开始长按检测');
        return;
      }
    }

    // 非聚焦状态下的处理
    if (gestureConfig.enableLongPress &&
        gestureConfig.enableDrag &&
        !shouldPreventGestureWhenHasCursor()) {
      _startLongPressDetection(event.localPosition);
      debugPrint('开始长按检测: ${event.localPosition}');
    }
  }

  /// 处理移动事件
  void _handlePointerMove(PointerMoveEvent event) {
    final delta = event.localPosition - _dragStartPosition!;
    final horizontalDistance = delta.dx.abs();
    final verticalDistance = delta.dy.abs();
    _totalDragDistance =
        sqrt(delta.dx * delta.dx + delta.dy * delta.dy); // 计算总的移动距离

    // 记录水平移动方向
    _recordHorizontalMovement(delta.dx, horizontalDistance);

    // debugPrint(
    //     '移动事件: hDistance=$horizontalDistance, vDistance=$verticalDistance, '
    //     'ratio=${horizontalDistance / (verticalDistance + 1)}, '
    //     'consistent=$_consistentHorizontalCount, '
    //     'isLongPressing=$_isLongPressing, isDragging=$_isDragging');

    // 拖拽处理（最高优先级）
    if (_isDragging) {
      _updateDragPosition(event.localPosition, event.position);
      return;
    }

    // 长按后开始拖拽
    if (_isLongPressing &&
        !_isDragging &&
        _totalDragDistance > gestureConfig.moveThreshold) {
      // debugPrint('长按后首次移动，开始拖拽: position=${event.localPosition}');
      _startDragging(event.localPosition);
      _updateDragPosition(event.localPosition);
      return;
    }

    // 滑动手势处理（严格限制，不能干扰拖拽）
    if (gestureConfig.enableSwipe &&
        !_isLongPressing &&
        !_isDragging &&
        verticalDistance < horizontalDistance && // 水平移动必须大于垂直移动
        _shouldTriggerSwipe(horizontalDistance, verticalDistance)) {
      final direction =
          delta.dx < 0 ? SwipeDirection.left : SwipeDirection.right;

      // 如果开始滑动，取消长按检测
      if (_swipeManager.startSwipe(this, direction, _totalDragDistance)) {
        _longPressTimer?.cancel();
        _longPressTimer = null;
        debugPrint('开始滑动: direction=$direction, distance=$_totalDragDistance');
      }
    }
  }

  /// 处理抬起事件
  void _handlePointerUp(PointerUpEvent event) {
    // debugPrint('抬起事件: isDragging=$_isDragging');

    if (_isDragging) {
      // 拖拽结束
      _cancelLongPressDetection();
      //  debugPrint('拖拽结束');
      return;
    }

    // 处理滑动手势结束
    final delta = event.localPosition - _dragStartPosition!;
    final horizontalDistance = delta.dx.abs();
    final verticalDistance = delta.dy.abs();

    if (!_isLongPressing &&
        !_isDragging &&
        gestureConfig.enableSwipe &&
        _shouldCompleteSwipe(horizontalDistance, verticalDistance) &&
        (_isSwipingLeft || _isSwipingRight)) {
      // 确保当前确实在滑动状态
      final direction =
          delta.dx < 0 ? SwipeDirection.left : SwipeDirection.right;

      // 只有在非聚焦状态下才触发滑动回调
      if (!hasFocus) {
        if (direction == SwipeDirection.left) {
          _onSwipeLeft?.call();
        } else {
          _onSwipeRight?.call();
        }
      }
      _swipeManager.selectComponent(this, direction);
      debugPrint(
          '滑动完成，触发选中: direction=$direction, horizontalDistance=$horizontalDistance');
    }

    // 结束滑动和长按检测
    _swipeManager.endSwipe(this);
    _cancelLongPressDetection();
    _resetGestureState();
  }

  /// 记录水平移动方向
  void _recordHorizontalMovement(double deltaX, double horizontalDistance) {
    if (horizontalDistance > 5.0) {
      _horizontalMovements.add(deltaX);
      if (_horizontalMovements.length > 5) {
        _horizontalMovements.removeAt(0);
      }

      // 检查方向一致性
      if (_horizontalMovements.length >= 2) {
        final lastMovement = _horizontalMovements.last;
        final secondLastMovement =
            _horizontalMovements[_horizontalMovements.length - 2];
        if ((lastMovement > 0) == (secondLastMovement > 0)) {
          _consistentHorizontalCount++;
        } else {
          _consistentHorizontalCount = 0;
        }
      }
    }
  }

  /// 开始长按检测
  void _startLongPressDetection(Offset position) {
    _longPressTimer?.cancel();
    _longPressTimer = Timer(gestureConfig.longPressDuration, () {
      if (!_isLongPressing && !_isDragging) {
        if (!_swipeManager.shouldAllowDrag(this)) {
          // debugPrint('长按检测: 当前组件不允许拖拽');
          return;
        }

        _isLongPressing = true;
        final success = _swipeManager.startDrag(this);
        if (!success) {
          // debugPrint('长按检测: SwipeStateManager拒绝拖拽');
          _isLongPressing = false;
          return;
        }

        _onLongPressStart?.call();
        // debugPrint('长按检测成功，进入长按状态');

        // 立即开始拖拽
        _isDragging = true;
        final globalPosition = localToGlobal(position);
        _swipeManager.updateDrag(globalPosition);
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
      _isDragging = false;
      _swipeManager.endDrag();
      _onDragEnd?.call();
      // debugPrint('取消长按检测，重置状态');
      markNeedsPaint();
    }
  }

  /// 开始拖拽
  void _startDragging(Offset position) {
    if (_isLongPressing) {
      _isDragging = true;
      final globalPosition = localToGlobal(position);
      _swipeManager.updateDrag(globalPosition);
      markNeedsPaint();
    }
  }

  /// 更新拖拽位置
  void _updateDragPosition(Offset localPosition,
      [Offset? screenGlobalPosition]) {
    if (_isDragging) {
      // 优先使用屏幕绝对坐标，如果没有则使用转换后的坐标
      final globalPosition =
          screenGlobalPosition ?? localToGlobal(localPosition);
      _swipeManager.updateDrag(globalPosition);
      markNeedsPaint();
    }
  }

  /// 检查是否应该触发滑动开始
  bool _shouldTriggerSwipe(double horizontalDistance, double verticalDistance) {
    if (horizontalDistance < gestureConfig.moveThreshold) return false;

    final ratio = horizontalDistance / (verticalDistance + 1.0);
    if (ratio < gestureConfig.horizontalToVerticalRatio) return false;

    if (_consistentHorizontalCount <
        gestureConfig.consistentDirectionSamples - 2) {
      return false;
    }

    return true;
  }

  /// 检查是否应该完成滑动操作
  bool _shouldCompleteSwipe(
      double horizontalDistance, double verticalDistance) {
    // 必须达到滑动阈值
    if (horizontalDistance < gestureConfig.swipeThreshold) return false;

    // 水平移动必须明显大于垂直移动
    final ratio = horizontalDistance / (verticalDistance + 1.0);
    if (ratio < gestureConfig.horizontalToVerticalRatio) return false;

    // 必须有足够的连续方向移动
    if (_consistentHorizontalCount < gestureConfig.consistentDirectionSamples) {
      return false;
    }

    return true;
  }

  /// 重置手势状态
  void _resetGestureState() {
    _horizontalMovements.clear();
    _consistentHorizontalCount = 0;
  }

  // SwipeableComponent 接口实现

  @override
  bool performSwipe(SwipeDirection direction, double offset) {
    switch (direction) {
      case SwipeDirection.left:
        if (!_isSwipingLeft) {
          _isSwipingLeft = true;
          _isSwipingRight = false;
          _swipeOffset = 0.0;
        }
        _swipeOffset = offset.clamp(0.0, gestureConfig.maxSwipeOffset);
        markNeedsPaint();
        return true;
      case SwipeDirection.right:
        if (!_isSwipingRight) {
          _isSwipingRight = true;
          _isSwipingLeft = false;
          _swipeOffset = 0.0;
        }
        _swipeOffset = offset.clamp(0.0, gestureConfig.maxSwipeOffset);
        markNeedsPaint();
        return true;
    }
  }

  @override
  void resetSwipe() {
    _isSwipingLeft = false;
    _isSwipingRight = false;
    _swipeOffset = 0.0;
    _dragStartPosition = null;
    _totalDragDistance = 0.0;
    _resetGestureState();
    markNeedsPaint();
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
    if (_isLongPressing) {
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
    _totalDragDistance = 0.0;
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
