import 'package:flutter/material.dart';

import '../../../document/nodes/node.dart';
import '../../../document/nodes/line.dart';
import '../../../document/nodes/block.dart';

/// 全局滑动状态管理器
/// 确保一次只能有一个组件处于滑动状态，并管理滚动冲突
class SwipeStateManager {
  static final SwipeStateManager _instance = SwipeStateManager._internal();
  factory SwipeStateManager() => _instance;
  SwipeStateManager._internal();

  /// 当前正在滑动的组件
  SwipeableComponent? _currentSwipingComponent;

  /// 当前选中的组件
  SwipeableComponent? _selectedComponent;

  /// 当前正在拖拽的组件
  SwipeableComponent? _currentDraggingComponent;

  /// 拖拽排序相关回调
  VoidCallback? _onDragStart;
  void Function(Offset globalPosition, SwipeableComponent draggingComponent)?
      _onDragUpdate;
  void Function(SwipeableComponent draggingComponent)? _onDragEnd;

  /// 滑动开始回调
  VoidCallback? _onSwipeStart;

  /// 滑动结束回调
  VoidCallback? _onSwipeEnd;

  /// 组件选中回调
  void Function(Line? line, Block? block, SwipeDirection direction)?
      _onComponentSelected;

  /// 检查是否应该阻止滚动事件（拖拽时）
  bool shouldPreventScroll() {
    return _currentDraggingComponent != null;
  }

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

  /// 设置拖拽排序回调
  void setDragCallbacks({
    VoidCallback? onDragStart,
    void Function(Offset globalPosition, SwipeableComponent draggingComponent)?
        onDragUpdate,
    void Function(SwipeableComponent draggingComponent)? onDragEnd,
  }) {
    _onDragStart = onDragStart;
    _onDragUpdate = onDragUpdate;
    _onDragEnd = onDragEnd;
  }

  /// 开始拖拽排序
  bool startDrag(SwipeableComponent component) {
    // 如果已有其他组件在拖拽，先结束它们
    if (_currentDraggingComponent != null &&
        _currentDraggingComponent != component) {
      _currentDraggingComponent!.endDrag();
    }

    _currentDraggingComponent = component;
    debugPrint('SwipeStateManager.startDrag: 开始拖拽 ${component.componentId}');
    _onDragStart?.call();
    return true;
  }

  /// 更新拖拽位置
  void updateDrag(Offset globalPosition) {
    if (_currentDraggingComponent != null) {
      debugPrint(
          'SwipeStateManager.updateDrag: 更新拖拽位置 $globalPosition, component=${_currentDraggingComponent!.componentId}');
      debugPrint(
          'SwipeStateManager.updateDrag: _onDragUpdate 回调是否为null: ${_onDragUpdate == null}');

      // 调用覆盖层更新位置
      // 需要导入 drag_sort_overlay.dart

      _onDragUpdate?.call(globalPosition, _currentDraggingComponent!);
    } else {
      debugPrint('SwipeStateManager.updateDrag: 没有正在拖拽的组件');
    }
  }

  /// 结束拖拽排序
  void endDrag() {
    if (_currentDraggingComponent != null) {
      final component = _currentDraggingComponent!;
      _currentDraggingComponent = null;
      component.endDrag();
      _onDragEnd?.call(component);
    }
  }

  /// 检查是否正在拖拽
  bool get isDragging => _currentDraggingComponent != null;

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
    if (_currentDraggingComponent != null) {
      _currentDraggingComponent!.endDrag();
      _currentDraggingComponent = null;
    }
    clearSelection();
  }

  /// 获取当前正在滑动的组件
  SwipeableComponent? get currentSwipingComponent => _currentSwipingComponent;

  /// 获取当前选中的组件
  SwipeableComponent? get selectedComponent => _selectedComponent;

  /// 获取当前正在拖拽的组件
  SwipeableComponent? get currentDraggingComponent => _currentDraggingComponent;
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

  /// 开始拖拽排序
  bool startDrag();

  /// 结束拖拽排序
  void endDrag();

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
