import 'package:flutter/material.dart';

import '../../../document/nodes/node.dart';
import '../../../document/nodes/line.dart';
import '../../../document/nodes/block.dart';

/// 全局滑动状态管理器
/// 确保一次只能有一个组件处于滑动状态
class SwipeStateManager {
  static final SwipeStateManager _instance = SwipeStateManager._internal();
  factory SwipeStateManager() => _instance;
  SwipeStateManager._internal();

  /// 当前正在滑动的组件
  SwipeableComponent? _currentSwipingComponent;

  /// 当前选中的组件
  SwipeableComponent? _selectedComponent;

  /// 滑动开始回调
  VoidCallback? _onSwipeStart;

  /// 滑动结束回调
  VoidCallback? _onSwipeEnd;

  /// 组件选中回调
  void Function(Line? line, Block? block, SwipeDirection direction)?
      _onComponentSelected;

  /// 设置滑动事件回调
  void setSwipeCallbacks({
    VoidCallback? onSwipeStart,
    VoidCallback? onSwipeEnd,
    void Function(Line? line, Block? block, SwipeDirection direction)?
        onComponentSelected,
  }) {
    _onSwipeStart = onSwipeStart;
    _onSwipeEnd = onSwipeEnd;
    _onComponentSelected = onComponentSelected;
  }

  /// 开始滑动
  /// 如果已有其他组件在滑动，会先重置它们
  bool startSwipe(
      SwipeableComponent component, SwipeDirection direction, double offset) {
    // 如果有其他组件正在滑动，先重置它们
    if (_currentSwipingComponent != null &&
        _currentSwipingComponent != component) {
      _currentSwipingComponent!.resetSwipe();
    }

    // 设置当前滑动组件
    _currentSwipingComponent = component;

    // 触发滑动开始回调
    if (_currentSwipingComponent != _selectedComponent) {
      _onSwipeStart?.call();
    }

    // 开始滑动
    return component.performSwipe(direction, offset);
  }

  /// 结束滑动
  void endSwipe(SwipeableComponent component) {
    if (_currentSwipingComponent == component) {
      _currentSwipingComponent = null;
    }
    component.endSwipe();
    _onSwipeEnd?.call();
  }

  /// 选中组件
  void selectComponent(SwipeableComponent component, SwipeDirection direction) {
    // 清除之前的选中状态
    if (_selectedComponent != null && _selectedComponent != component) {
      _selectedComponent!.setSelected(false);
    }

    // 设置新的选中组件
    _selectedComponent = component;
    component.setSelected(true);

    // 触发选中回调
    _onComponentSelected?.call(component.lineNode, component.block, direction);
  }

  /// 清除选中状态
  void clearSelection() {
    if (_selectedComponent != null) {
      _selectedComponent!.setSelected(false);
      _selectedComponent = null;
    }
  }

  /// 重置所有滑动状态
  void resetAll() {
    if (_currentSwipingComponent != null) {
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }
    clearSelection();
  }

  /// 获取当前正在滑动的组件
  SwipeableComponent? get currentSwipingComponent => _currentSwipingComponent;

  /// 获取当前选中的组件
  SwipeableComponent? get selectedComponent => _selectedComponent;
}

/// 滑动方向枚举
enum SwipeDirection { left, right }

/// 可滑动组件接口
abstract class SwipeableComponent {
  /// 执行滑动操作
  bool performSwipe(SwipeDirection direction, double offset);

  /// 结束滑动
  void endSwipe();

  /// 重置滑动状态
  void resetSwipe();

  /// 设置选中状态
  void setSelected(bool selected);

  /// 获取组件标识符（用于调试）
  String get componentId;

  /// 获取组件的文本内容（用于弹窗显示）
  String get textContent;

  /// 获取对应的文档节点，用于QuillController操作
  Node get documentNode;

  /// 获取文档偏移量
  int get documentOffset;

  /// 获取文档长度
  int get documentLength;

  /// 如果是TextLine组件，返回对应的Line节点
  Line? get lineNode => null;

  /// 如果是TextBlock组件，返回对应的Block节点
  Block? get block => null;
}
