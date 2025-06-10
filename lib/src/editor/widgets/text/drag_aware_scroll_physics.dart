import 'package:flutter/material.dart';
import 'swipe_manager.dart';

/// 支持拖拽时禁用滚动的自定义ScrollPhysics
/// 当SwipeStateManager检测到拖拽状态时，会禁用滚动
///
/// 可以应用到任何ScrollView组件：
/// - QuillEditor内部的SingleChildScrollView
/// - 外层的ListView/SingleChildScrollView
/// - CustomScrollView等
class DragAwareScrollPhysics extends ScrollPhysics {
  const DragAwareScrollPhysics({
    super.parent,
    this.swipeManager,
  });

  /// 创建一个使用全局SwipeStateManager实例的DragAwareScrollPhysics
  factory DragAwareScrollPhysics.global({ScrollPhysics? parent}) {
    return DragAwareScrollPhysics(
      parent: parent,
      swipeManager: SwipeStateManager(),
    );
  }

  final SwipeStateManager? swipeManager;

  @override
  DragAwareScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return DragAwareScrollPhysics(
      parent: buildParent(ancestor),
      swipeManager: swipeManager,
    );
  }

  @override
  bool shouldAcceptUserOffset(ScrollMetrics position) {
    // 如果正在拖拽或滑动，不接受用户滚动
    if (swipeManager?.shouldPreventOtherGestures() == true) {
      return false;
    }
    return super.shouldAcceptUserOffset(position);
  }

  @override
  double applyPhysicsToUserOffset(ScrollMetrics position, double offset) {
    // 如果正在拖拽或滑动，返回0阻止滚动
    if (swipeManager?.shouldPreventOtherGestures() == true) {
      return 0;
    }
    return super.applyPhysicsToUserOffset(position, offset);
  }

  @override
  Simulation? createBallisticSimulation(
      ScrollMetrics position, double velocity) {
    // 如果正在拖拽或滑动，不创建惯性滚动
    if (swipeManager?.shouldPreventOtherGestures() == true) {
      return null;
    }
    return super.createBallisticSimulation(position, velocity);
  }
}
