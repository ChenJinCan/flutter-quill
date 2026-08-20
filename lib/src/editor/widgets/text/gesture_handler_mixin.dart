// ignore_for_file: cascade_invocations

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'swipe_manager.dart';

/// 手势状态重置修复说明:
///
/// 问题: TextLine左侧滑动有时会导致界面完全不响应
/// 原因: 滑动状态没有正确重置，导致手势检测器处于异常状态
///
/// 修复方案:
/// 1. 强化状态重置逻辑，确保所有状态变量都被正确重置
/// 2. 添加紧急状态重置方法，用于处理异常情况
/// 3. 在指针取消事件中使用更强的重置逻辑
/// 4. 添加异常处理，防止SwipeStateManager错误影响本地状态重置
/// 5. 提供公共方法供外部强制重置状态
///
/// 使用方法:
/// - 如果界面不响应，可以调用 forceResetGestureStates() 强制重置
/// - 可以通过 hasActiveGestureState 检查是否有活跃的手势状态

/// 手势模式枚举
enum GestureMode {
  editing, // 编辑模式：原生手势优先
  organizing, // 组织模式：自定义手势优先
}

/// 手势处理配置类
class GestureConfig {
  const GestureConfig({
    this.mode = GestureMode.editing,
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

  /// 手势模式
  final GestureMode mode;

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

  /// Local content bounds used by drag and swipe-selection backgrounds.
  /// Text lines override this so asymmetric editor padding does not make the
  /// distance above and below the glyphs look different.
  Rect get swipeEffectLocalBounds => Offset.zero & size;

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
  int? _rowSelectionPointer;

  bool get _supportsRowSelection => _swipeManager.canSelectComponent(this);

  Rect get _rowSelectionHitRect {
    final bounds = swipeEffectLocalBounds;
    return Rect.fromCenter(
      center: Offset(size.width - 18, bounds.center.dy),
      width: 44,
      height: 44,
    );
  }

  bool get hasActiveRowSelectionControls =>
      _swipeManager.isSelectionModeActive && _supportsRowSelection;

  Color get rowSelectionSurfaceColor => const Color(0xFFFFFFFF);
  Color get rowSelectionOutlineColor => const Color(0xFF718096);

  void describeRowSelectionSemantics(SemanticsConfiguration config) {
    if (!hasActiveRowSelectionControls) return;

    config
      ..isSemanticBoundary = true
      ..isSelected = _isSelected
      ..onTap = () {
        _swipeManager.toggleComponentSelection(this);
        HapticFeedback.selectionClick();
      };
  }

  void _selectionModeChanged() {
    if (!attached) return;
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(covariant PipelineOwner owner) {
    super.attach(owner);
    _swipeManager.selectionModeListenable.addListener(_selectionModeChanged);
  }

  @override
  void detach() {
    _swipeManager.selectionModeListenable.removeListener(_selectionModeChanged);
    super.detach();
  }

  // 双击检测相关
  Timer? _doubleTapTimer;
  Offset? _lastTapPosition;
  bool _isInDoubleTapWindow = false;

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

    // 获取当前手势模式
    final isEditingMode = gestureConfig.mode == GestureMode.editing;

    // 检查是否有光标显示在当前组件上
    final hasCursorOnThisComponent =
        hasFocus && shouldPreventGestureWhenHasCursor();

    // 编辑模式下的处理
    if (isEditingMode) {
      // 如果有光标在当前组件，禁用滑动手势，但允许拖拽（会在长按检测时再次检查）
      if (hasCursorOnThisComponent) {
        debugPrint('编辑模式：光标在当前组件，禁用滑动但允许检测拖拽');
        return gestureConfig.enableDrag || gestureConfig.enableLongPress;
      }

      // 如果有焦点但光标不在当前组件，允许拖拽和长按
      if (hasFocus) {
        return true;
      }
    }

    // 组织模式下，允许所有手势
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

  /// 处理双击检测
  bool _handleDoubleTapDetection(Offset globalPosition) {
    if (_doubleTapTimer != null && _lastTapPosition != null) {
      // 检查是否在双击容忍范围内
      final distance = (globalPosition - _lastTapPosition!).distance;
      if (distance <= kDoubleTapSlop) {
        // 检测到双击
        debugPrint('检测到双击，禁用长按拖拽手势');
        _isInDoubleTapWindow = true;
        _cancelDoubleTapTimer();
        _cancelLongPressDetection();
        return true;
      }
    }
    return false;
  }

  /// 开始双击检测窗口
  void _startDoubleTapDetection(Offset globalPosition) {
    _lastTapPosition = globalPosition;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = Timer(kDoubleTapTimeout, () {
      _lastTapPosition = null;
      _doubleTapTimer = null;
      _isInDoubleTapWindow = false;
    });
  }

  /// 取消双击检测
  void _cancelDoubleTapTimer() {
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;
    _lastTapPosition = null;
  }

  /// 处理指针事件的通用逻辑
  ///
  /// 新的简化策略：
  /// 1. 每个组件独立处理自己的手势
  /// 2. 优先级：拖拽 > 滚动 > 滑动
  /// 3. 移除复杂的组件间冲突检查
  void handleGestureEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (_handleRowSelectionControl(event)) {
      return;
    }

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

  bool _handleRowSelectionControl(PointerEvent event) {
    if (!_swipeManager.isSelectionModeActive || !_supportsRowSelection) {
      _rowSelectionPointer = null;
      return false;
    }

    if (event is PointerDownEvent) {
      if (_rowSelectionHitRect.contains(event.localPosition)) {
        _rowSelectionPointer = event.pointer;
        return true;
      }
      // The editor-level tap handlers remain disabled in row-selection mode,
      // so an ordinary tap cannot move the caret. Let non-control pointers
      // continue through the swipe recognizer so a new swipe stays exclusive.
      return false;
    }

    if (_rowSelectionPointer == null || event.pointer != _rowSelectionPointer) {
      return false;
    }

    if (event is PointerUpEvent) {
      final shouldToggle = _rowSelectionHitRect.contains(event.localPosition);
      _rowSelectionPointer = null;
      if (shouldToggle) {
        _swipeManager.toggleComponentSelection(this);
        HapticFeedback.selectionClick();
      }
      return true;
    }

    if (event is PointerCancelEvent) {
      _rowSelectionPointer = null;
    }
    return true;
  }

  /// 处理按下事件
  void _handlePointerDown(PointerDownEvent event) {
    // 检测双击
    final isDoubleTap = _handleDoubleTapDetection(event.position);
    if (isDoubleTap) {
      // 双击场景下不启动任何自定义手势
      debugPrint('双击检测成功，跳过自定义手势启动');
      return;
    }

    // 开始新的双击检测窗口
    _startDoubleTapDetection(event.position);

    // 重置当前组件的状态
    _dragStartPosition = event.localPosition;
    _horizontalMovements.clear();

    debugPrint('PointerDown: 开始新的手势检测 ${event.localPosition}');

    // 根据手势模式决定是否启动长按检测
    final isEditingMode = gestureConfig.mode == GestureMode.editing;

    // 编辑模式下，如果有光标在当前组件，不启动自定义手势
    if (isEditingMode && hasFocus && shouldPreventGestureWhenHasCursor()) {
      debugPrint('编辑模式且光标在当前组件，不启动自定义手势检测');
      return;
    }

    // 启动长按检测（用于拖拽）- 但要避免双击冲突
    if (gestureConfig.enableLongPress &&
        gestureConfig.enableDrag &&
        !_isInDoubleTapWindow) {
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

    // 编辑模式下的特殊处理
    final isEditingMode = gestureConfig.mode == GestureMode.editing;

    // 如果在双击窗口内有移动，取消长按检测（避免误触发拖拽）
    if (_isInDoubleTapWindow && horizontalDistance > 5.0) {
      _cancelLongPressDetection();
      debugPrint('双击窗口内检测到移动，取消长按检测');
      return;
    }

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

    // 滑动检测（编辑模式下有焦点时禁用）
    if (gestureConfig.enableSwipe &&
        !_isLongPressing &&
        !_isDragging &&
        !_isScrolling &&
        !_isInDoubleTapWindow &&
        !(isEditingMode && hasFocus) &&
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
        '抬起事件: isDragging=$_isDragging, isLongPressing=$_isLongPressing, isSwipingLeft=$_isSwipingLeft, isSwipingRight=$_isSwipingRight, isInDoubleTapWindow=$_isInDoubleTapWindow');

    // 如果正在拖拽，结束拖拽
    if (_isDragging) {
      _handleDragEnd();
      return;
    }

    // 如果在双击窗口内，清除双击状态但不执行其他手势
    if (_isInDoubleTapWindow) {
      debugPrint('双击窗口内抬起，清除双击状态');
      _isInDoubleTapWindow = false;
      _resetGestureDetectionStates();
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
          try {
            if (direction == SwipeDirection.left) {
              _onSwipeLeft?.call();
            } else {
              _onSwipeRight?.call();
            }
          } catch (e) {
            debugPrint('滑动回调执行失败: $e');
          }
        }

        // 设置选中状态
        _isSelected = true;
        debugPrint('设置组件为选中状态');

        // 调用SwipeStateManager的选中回调
        try {
          _swipeManager.selectComponent(this, direction);
          debugPrint('触发ComponentSelect回调');
        } catch (e) {
          debugPrint('ComponentSelect回调执行失败: $e');
        }
      } else {
        SwipeStateManager().clearCurrentSwipingComponent();
      }

      // 强制重置滑动状态，确保界面能响应
      debugPrint('强制重置滑动状态');
      _isSwipingLeft = false;
      _isSwipingRight = false;
      _swipeOffset = 0.0;
      markNeedsPaint();
      debugPrint('滑动状态重置完成');
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
      // 在长按定时器触发时再次检查是否有滚动发生或者是双击场景
      if (_isScrolling) {
        debugPrint('长按定时器触发时检测到滚动，取消长按拖拽');
        return;
      }

      if (_isInDoubleTapWindow) {
        debugPrint('长按定时器触发时检测到双击窗口，取消长按拖拽');
        return;
      }

      // 编辑模式下的特殊处理：只有当光标在当前组件时才阻止拖拽
      final isEditingMode = gestureConfig.mode == GestureMode.editing;
      if (isEditingMode && hasFocus && shouldPreventGestureWhenHasCursor()) {
        debugPrint('编辑模式且光标在当前组件，不处理自定义长按拖拽');
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
      // 添加触觉反馈
      HapticFeedback.mediumImpact();
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
    debugPrint('重置手势状态');
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
    debugPrint('指针取消事件: 执行紧急状态重置');
    _emergencyStateReset();
  }

  /// 紧急状态重置 - 用于处理异常情况
  void _emergencyStateReset() {
    debugPrint('_emergencyStateReset: 执行紧急状态重置');

    // 立即停止所有定时器
    _longPressTimer?.cancel();
    _longPressTimer = null;
    _doubleTapTimer?.cancel();
    _doubleTapTimer = null;

    // 强制重置所有状态变量
    _dragStartPosition = null;
    _isSwipingLeft = false;
    _isSwipingRight = false;
    _swipeOffset = 0.0;
    _isDragging = false;
    _isLongPressing = false;
    _isInDoubleTapWindow = false;
    _lastTapPosition = null;

    // 清空移动记录
    _horizontalMovements.clear();

    // 强制重绘
    markNeedsPaint();

    // 尝试清理SwipeStateManager状态（忽略错误）
    try {
      _swipeManager.resetAll();
    } catch (e) {
      debugPrint('_emergencyStateReset: SwipeStateManager重置失败，忽略: $e');
    }

    debugPrint('_emergencyStateReset: 紧急重置完成');
  }

  /// 重置所有手势状态
  void _resetAllGestureStates() {
    debugPrint('_resetAllGestureStates: 开始重置所有状态');

    // 强制重置本地状态，不依赖外部状态检查
    final wasSwipingLeft = _isSwipingLeft;
    final wasSwipingRight = _isSwipingRight;
    final wasDragging = _isDragging;
    final wasLongPressing = _isLongPressing;

    // 立即清除所有本地状态
    _dragStartPosition = null;
    _isSwipingLeft = false;
    _isSwipingRight = false;
    _swipeOffset = 0.0;
    _isDragging = false;
    _isLongPressing = false;
    _isInDoubleTapWindow = false;

    // 取消所有定时器
    _cancelLongPressDetection();
    _cancelDoubleTapTimer();
    _resetGestureState();

    // 如果之前有任何滑动或拖拽状态，强制重绘
    if (wasSwipingLeft || wasSwipingRight || wasDragging || wasLongPressing) {
      markNeedsPaint();
      debugPrint('_resetAllGestureStates: 强制重绘界面');
    }

    // 通知SwipeStateManager清理状态（但不依赖其返回值）
    try {
      if (_swipeManager.currentSwipingComponent == this) {
        debugPrint('_resetAllGestureStates: 通知SwipeStateManager结束滑动');
        _swipeManager.endSwipe(this);
      }
    } catch (e) {
      debugPrint('_resetAllGestureStates: SwipeStateManager清理失败，继续执行: $e');
    }

    debugPrint('_resetAllGestureStates: 状态重置完成');
  }

  /// 重置手势检测状态（不影响滑动选中状态）
  void _resetGestureDetectionStates() {
    debugPrint('_resetGestureDetectionStates: 重置手势检测状态');
    _dragStartPosition = null;
    _cancelLongPressDetection();
    _resetGestureState();
    _isInDoubleTapWindow = false;
    debugPrint('_resetGestureDetectionStates: 重置完成');
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
      markNeedsSemanticsUpdate();
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
    _cancelDoubleTapTimer();
    _isInDoubleTapWindow = false;
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
        swipeEffectLocalBounds.shift(effectiveOffset),
        const Radius.circular(4),
      );
      context.canvas.drawRRect(dragRRect, dragPaint);
    }

    // 绘制选中状态背景
    if (_isSelected && !_isDragging) {
      final selectedPaint = Paint()
        ..color = const Color(0xFF2196F3).withValues(alpha: 0.2);
      final selectedRRect = RRect.fromRectAndRadius(
        swipeEffectLocalBounds.shift(effectiveOffset),
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

  /// Paints the explicit row selection control above the line contents.
  void paintRowSelectionControl(PaintingContext context, Offset offset) {
    if (!_swipeManager.isSelectionModeActive || !_supportsRowSelection) return;

    final center = offset + _rowSelectionHitRect.center;
    const accentColor = Color(0xFF2B6CB0);
    final fill = Paint()
      ..color = _isSelected ? accentColor : rowSelectionSurfaceColor
      ..style = PaintingStyle.fill;
    final outline = Paint()
      ..color = _isSelected ? accentColor : rowSelectionOutlineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    context.canvas
      ..drawCircle(center, 11, fill)
      ..drawCircle(center, 11, outline);
    if (_isSelected) {
      final check = Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()
        ..moveTo(center.dx - 5, center.dy)
        ..lineTo(center.dx - 1.5, center.dy + 3.5)
        ..lineTo(center.dx + 5.5, center.dy - 4);
      context.canvas.drawPath(path, check);
    }
  }

  Offset? _lastEffectiveOffset;
  Offset get effectiveOffset => _lastEffectiveOffset ?? Offset.zero;

  /// 获取当前是否正在向左滑动
  bool get isSwipingLeft => _isSwipingLeft;

  /// 获取当前是否正在向右滑动
  bool get isSwipingRight => _isSwipingRight;

  /// 检查是否处于长按状态
  bool get isLongPressing => _isLongPressing;

  /// 公共方法：强制重置所有手势状态
  /// 用于在界面不响应时从外部强制重置
  void forceResetGestureStates() {
    debugPrint('forceResetGestureStates: 外部调用强制重置');
    _emergencyStateReset();
  }

  /// 公共方法：检查当前是否有活跃的手势状态
  bool get hasActiveGestureState {
    return _isSwipingLeft ||
        _isSwipingRight ||
        _isDragging ||
        _isLongPressing ||
        _isInDoubleTapWindow ||
        _dragStartPosition != null ||
        _longPressTimer != null ||
        _doubleTapTimer != null;
  }
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
