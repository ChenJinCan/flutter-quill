import 'package:flutter/material.dart';

import '../../../controller/quill_controller.dart';
import '../../../document/nodes/block.dart';
import '../../../document/nodes/line.dart';
import '../../../document/nodes/node.dart';

/// 全局滑动状态管理器
/// 确保一次只能有一个组件处于滑动状态，并管理滚动冲突
class SwipeStateManager {
  factory SwipeStateManager() => _instance;
  SwipeStateManager._internal();
  static final SwipeStateManager _instance = SwipeStateManager._internal();

  /// 当前正在滑动的组件
  SwipeableComponent? _currentSwipingComponent;

  /// 当前选中的组件
  SwipeableComponent? _selectedComponent;

  /// 当前正在拖拽的组件
  SwipeableComponent? _currentDraggingComponent;

  /// QuillController引用，用于在拖拽时取消focus
  QuillController? _controller;

  /// ScrollController引用，用于监听滚动事件
  ScrollController? get scrollController => _scrollController;

  /// FocusNode引用，用于在拖拽时取消focus
  FocusNode? _focusNode;

  /// ScrollController引用，用于监听滚动事件
  ScrollController? _scrollController;

  /// 焦点监听器是否已添加
  bool _focusListenerAdded = false;

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
  void Function(Line? line, Block? block, SwipeDirection direction,
      int documentOffset, int documentLength)? _onComponentSelected;

  /// 焦点聚焦时隐藏拖拽覆盖层的回调
  VoidCallback? _onHideDragOverlay;

  /// 设置编辑器引用，用于在拖拽时取消focus和监听滚动
  void setEditorReferences({
    QuillController? controller,
    FocusNode? focusNode,
    ScrollController? scrollController,
  }) {
    // 移除旧的焦点监听器
    if (_focusListenerAdded && _focusNode != null) {
      _focusNode!.removeListener(_onFocusChanged);
      _focusListenerAdded = false;
    }

    _controller = controller;
    _focusNode = focusNode;

    // 添加新的焦点监听器
    if (_focusNode != null) {
      _focusNode!.addListener(_onFocusChanged);
      _focusListenerAdded = true;
    }

    // 如果有新的ScrollController，先移除旧的监听器再添加新的
    if (_scrollController != scrollController) {
      _scrollController?.removeListener(_onScrollChanged);
      _scrollController = scrollController;
      _scrollController?.addListener(_onScrollChanged);
    }
  }

  /// 焦点变化监听器 - 当焦点聚焦时立即清除所有滑动和拖拽状态
  void _onFocusChanged() {
    // 当编辑器获得焦点时，立即清除所有滑动和拖拽状态
    if (_focusNode?.hasFocus == true) {
      // debugPrint('SwipeStateManager._onFocusChanged: 编辑器获得焦点，清除所有滑动和拖拽状态');
      _clearAllStatesOnFocus();
    }
  }

  /// 在焦点聚焦时清除所有状态的私有方法
  void _clearAllStatesOnFocus() {
    // 清除当前滑动状态
    if (_currentSwipingComponent != null) {
      // debugPrint('SwipeStateManager._clearAllStatesOnFocus: 重置滑动状态');
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }

    // 清除当前拖拽状态
    if (_currentDraggingComponent != null) {
      // debugPrint('SwipeStateManager._clearAllStatesOnFocus: 结束拖拽状态');
      _currentDraggingComponent!.endDrag();
      _currentDraggingComponent = null;
    }

    // 清除选中状态
    if (_selectedComponent != null) {
      // debugPrint('SwipeStateManager._clearAllStatesOnFocus: 清除选中状态');
      _selectedComponent!.setSelected(false);
      _selectedComponent = null;
    }

    // 隐藏拖拽覆盖层（如果存在）
    // 注意：这里使用动态导入避免循环依赖
    try {
      // 导入drag_sort_overlay.dart并调用hideOnFocus
      _hideDragOverlayOnFocus();
    } catch (e) {
      // debugPrint('SwipeStateManager._clearAllStatesOnFocus: 隐藏拖拽覆盖层失败: $e');
    }
  }

  /// 隐藏拖拽覆盖层的私有方法（避免循环依赖）
  void _hideDragOverlayOnFocus() {
    // 通过回调方式通知DragSortOverlay隐藏
    _onHideDragOverlay?.call();
  }

  /// 滚动事件监听器 - 在滚动时重置所有滑动状态
  void _onScrollChanged() {
    debugPrint('SwipeStateManager: 检测到滚动，清除所有组件状态');

    // 如果有组件在滑动状态，重置它们
    if (_currentSwipingComponent != null) {
      debugPrint('SwipeStateManager: 重置当前滑动组件');
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }

    // 清除选中状态（如果存在）
    if (_selectedComponent != null) {
      debugPrint('SwipeStateManager: 清除当前选中组件');
      _selectedComponent!.setSelected(false);
      _selectedComponent = null;
    }

    // 通知所有组件清除其选中状态（全局清理）
    _clearAllComponentsSelection();
  }

  /// 清除所有组件的选中状态
  void _clearAllComponentsSelection() {
    // 通过SwipeEnd回调来通知编辑器重新绘制，这样所有组件都会重置状态
    _onSwipeEnd?.call();
  }

  /// 检查是否应该阻止滚动事件（拖拽时）
  bool shouldPreventScroll() {
    return _currentDraggingComponent != null;
  }

  /// 检查是否正在滑动（任何类型的滑动）
  bool get isSwipingOrDragging =>
      _currentSwipingComponent != null || _currentDraggingComponent != null;

  /// 检查是否应该阻止其他手势（当有任何活动状态时）
  bool shouldPreventOtherGestures() {
    final hasActiveSwipe = safeCurrentSwipingComponent != null;
    final hasActiveDrag = safeCurrentDraggingComponent != null;
    debugPrint(
        'SwipeStateManager.shouldPreventOtherGestures: hasActiveSwipe=$hasActiveSwipe, hasActiveDrag=$hasActiveDrag');
    return hasActiveSwipe || hasActiveDrag;
  }

  /// 设置滑动事件回调
  void setSwipeCallbacks({
    VoidCallback? onSwipeStart,
    VoidCallback? onSwipeEnd,
    void Function(Line? line, Block? block, SwipeDirection direction,
            int documentOffset, int documentLength)?
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
    VoidCallback? onHideDragOverlay,
  }) {
    _onDragStart = onDragStart;
    _onDragUpdate = onDragUpdate;
    _onDragEnd = onDragEnd;
    _onHideDragOverlay = onHideDragOverlay;
  }

  /// 检查指定组件是否应该允许拖拽
  /// 当有焦点时，只有当前光标所在的TextLine被禁止拖拽，其他的允许拖拽
  bool shouldAllowDrag(SwipeableComponent component) {
    // 如果没有焦点，允许所有拖拽
    if (_focusNode?.hasFocus != true || _controller == null) {
      return true;
    }

    // 如果不是TextLine组件，允许拖拽
    if (component.lineNode == null) {
      return true;
    }

    // 检查当前组件是否包含光标
    final selection = _controller!.selection;
    if (!selection.isValid || !selection.isCollapsed) {
      return true; // 如果没有有效的光标或有选择范围，允许拖拽
    }

    final cursorOffset = selection.baseOffset;
    final lineStartOffset = component.documentOffset;
    final lineEndOffset = lineStartOffset + component.documentLength;

    // 如果光标在当前TextLine范围内，禁止拖拽
    if (cursorOffset >= lineStartOffset && cursorOffset < lineEndOffset) {
      // debugPrint('SwipeStateManager.shouldAllowDrag: 光标在当前TextLine，禁止拖拽');
      return false;
    }

    return true;
  }

  /// 开始拖拽排序
  bool startDrag(SwipeableComponent component) {
    // 检查是否应该允许拖拽
    if (!shouldAllowDrag(component)) {
      // debugPrint('SwipeStateManager.startDrag: 当前组件不允许拖拽');
      return false;
    }

    // 如果已有其他组件在拖拽，先结束它们
    if (_currentDraggingComponent != null &&
        _currentDraggingComponent != component) {
      _currentDraggingComponent!.endDrag();
    }

    // 如果有其他组件在滑动，先重置它们
    if (_currentSwipingComponent != null &&
        _currentSwipingComponent != component) {
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }

    // 清除之前的选中状态（如果不是当前组件）
    if (_selectedComponent != null && _selectedComponent != component) {
      _selectedComponent!.setSelected(false);
      _selectedComponent = null;
    }

    // 开始拖拽时取消编辑器焦点
    if (_focusNode?.hasFocus == true) {
      // debugPrint('SwipeStateManager.startDrag: 取消编辑器焦点');
      _focusNode!.unfocus();
    }

    _currentDraggingComponent = component;
    debugPrint('SwipeStateManager.startDrag: 开始拖拽 ${component.componentId}');
    _onDragStart?.call();
    debugPrint('SwipeStateManager.startDrag: 拖拽开始回调已调用');
    return true;
  }

  /// 更新拖拽位置
  void updateDrag(Offset globalPosition) {
    if (_currentDraggingComponent != null) {
      debugPrint('SwipeStateManager.updateDrag: 更新拖拽位置 $globalPosition');
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

      // 触发拖拽完成的文档重排序操作
      try {
        // 使用动态导入避免循环依赖
        // 通过回调方式处理拖拽完成
        _onDragEnd?.call(component);
      } catch (e) {
        // debugPrint('SwipeStateManager.endDrag: 拖拽完成处理失败: $e');
      }
    }
  }

  /// 检查是否正在拖拽
  bool get isDragging => safeCurrentDraggingComponent != null;

  /// 开始滑动
  /// 如果已有其他组件在滑动，会先重置它们
  bool startSwipe(
      SwipeableComponent component, SwipeDirection direction, double offset) {
    debugPrint(
        'SwipeStateManager.startSwipe: 尝试开始滑动 ${component.componentId}, direction=$direction, offset=$offset');

    // 首先清理所有无效的组件引用
    safeCurrentSwipingComponent; // 触发清理检查
    safeCurrentDraggingComponent; // 触发清理检查
    safeSelectedComponent; // 触发清理检查

    // 如果有组件正在拖拽，不允许开始滑动
    if (_currentDraggingComponent != null) {
      debugPrint('SwipeStateManager.startSwipe: 有组件正在拖拽，拒绝滑动');
      return false;
    }

    // 当有焦点时，全局禁止左右滑动操作
    if (_focusNode?.hasFocus == true) {
      debugPrint('SwipeStateManager.startSwipe: 编辑器有焦点，禁止滑动操作');
      return false;
    }

    // 如果有其他组件在滑动，先重置它们
    if (_currentSwipingComponent != null &&
        _currentSwipingComponent != component) {
      // debugPrint('SwipeStateManager.startSwipe: 重置其他组件的滑动状态');
      _currentSwipingComponent!.resetSwipe();
    }

    // 清除之前的选中状态（如果不是当前组件）
    if (_selectedComponent != null && _selectedComponent != component) {
      _selectedComponent!.setSelected(false);
      _selectedComponent = null;
    }

    // 设置当前滑动组件
    _currentSwipingComponent = component;

    // 触发滑动开始回调
    if (_currentSwipingComponent != _selectedComponent) {
      _onSwipeStart?.call();
      debugPrint(
          'SwipeStateManager.startSwipe: 触发滑动开始回调 ${component.componentId}');
    }

    // 开始滑动
    final result = component.performSwipe(direction, offset);
    debugPrint('SwipeStateManager.startSwipe: performSwipe 返回结果=$result');
    return result;
  }

  /// 结束滑动
  void endSwipe(SwipeableComponent component) {
    debugPrint(
        'SwipeStateManager.endSwipe: 组件=${component.componentId}, 当前滑动组件=${_currentSwipingComponent?.componentId}');
    if (_currentSwipingComponent == component) {
      _currentSwipingComponent = null;
      debugPrint('SwipeStateManager.endSwipe: 清理当前滑动组件');
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

    // 清除当前滑动状态
    if (_currentSwipingComponent != null) {
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }

    // 清除当前拖拽状态
    if (_currentDraggingComponent != null) {
      _currentDraggingComponent!.endDrag();
      _currentDraggingComponent = null;
    }

    // 设置新的选中组件
    _selectedComponent = component;
    component.setSelected(true);

    // 触发选中回调，增加documentOffset和documentLength参数
    _onComponentSelected?.call(component.lineNode, component.block, direction,
        component.documentOffset, component.documentLength);
  }

  /// 清除选中状态
  void clearSelection() {
    if (_selectedComponent != null) {
      _selectedComponent!.setSelected(false);
      _selectedComponent = null;
    }
  }

  /// 安全清理当前滑动组件（不触发其他回调）
  void clearCurrentSwipingComponent() {
    debugPrint(
        'SwipeStateManager.clearCurrentSwipingComponent: 清理当前滑动组件=${_currentSwipingComponent?.componentId}');
    _currentSwipingComponent = null;
  }

  /// 重置所有滑动状态
  void resetAll() {
    debugPrint('SwipeStateManager.resetAll: 重置所有状态');
    if (_currentSwipingComponent != null) {
      debugPrint(
          'SwipeStateManager.resetAll: 重置滑动组件=${_currentSwipingComponent!.componentId}');
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }
    if (_currentDraggingComponent != null) {
      debugPrint(
          'SwipeStateManager.resetAll: 重置拖拽组件=${_currentDraggingComponent!.componentId}');
      _currentDraggingComponent!.endDrag();
      _currentDraggingComponent = null;
    }
    clearSelection();
    debugPrint('SwipeStateManager.resetAll: 重置完成');
  }

  /// 获取当前正在滑动的组件（安全访问）
  SwipeableComponent? get currentSwipingComponent =>
      safeCurrentSwipingComponent;

  /// 获取当前选中的组件（安全访问）
  SwipeableComponent? get selectedComponent => safeSelectedComponent;

  /// 获取当前正在拖拽的组件（安全访问）
  SwipeableComponent? get currentDraggingComponent =>
      safeCurrentDraggingComponent;

  /// 清理资源，移除所有监听器
  void dispose() {
    // 移除焦点监听器
    if (_focusListenerAdded && _focusNode != null) {
      _focusNode!.removeListener(_onFocusChanged);
      _focusListenerAdded = false;
    }

    // 移除滚动监听器
    _scrollController?.removeListener(_onScrollChanged);
    _scrollController = null;
    _controller = null;
    _focusNode = null;
    resetAll();
  }

  /// 检查组件是否仍然有效（未被释放）
  bool _isComponentValid(SwipeableComponent? component) {
    if (component == null) return false;

    try {
      // 尝试访问组件的基本属性，如果组件已被释放会抛出异常
      final _ = component.componentId;
      return true;
    } catch (e) {
      debugPrint('SwipeStateManager._isComponentValid: 组件已被释放 - $e');
      return false;
    }
  }

  /// 安全获取当前滑动组件（检查有效性）
  SwipeableComponent? get safeCurrentSwipingComponent {
    if (_currentSwipingComponent != null &&
        !_isComponentValid(_currentSwipingComponent)) {
      debugPrint('SwipeStateManager: 当前滑动组件已被释放，自动清理');
      _currentSwipingComponent = null;
    }
    return _currentSwipingComponent;
  }

  /// 安全获取当前拖拽组件（检查有效性）
  SwipeableComponent? get safeCurrentDraggingComponent {
    if (_currentDraggingComponent != null &&
        !_isComponentValid(_currentDraggingComponent)) {
      debugPrint('SwipeStateManager: 当前拖拽组件已被释放，自动清理');
      _currentDraggingComponent = null;
    }
    return _currentDraggingComponent;
  }

  /// 安全获取选中组件（检查有效性）
  SwipeableComponent? get safeSelectedComponent {
    if (_selectedComponent != null && !_isComponentValid(_selectedComponent)) {
      debugPrint('SwipeStateManager: 选中组件已被释放，自动清理');
      _selectedComponent = null;
    }
    return _selectedComponent;
  }
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
