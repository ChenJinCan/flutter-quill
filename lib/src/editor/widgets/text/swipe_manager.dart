/// 全局滑动状态管理器
/// 确保一次只能有一个组件处于滑动状态
class SwipeStateManager {
  static final SwipeStateManager _instance = SwipeStateManager._internal();
  factory SwipeStateManager() => _instance;
  SwipeStateManager._internal();

  /// 当前正在滑动的组件
  SwipeableComponent? _currentSwipingComponent;

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

    // 开始滑动
    return component.performSwipe(direction, offset);
  }

  /// 结束滑动
  void endSwipe(SwipeableComponent component) {
    if (_currentSwipingComponent == component) {
      _currentSwipingComponent = null;
    }
    component.endSwipe();
  }

  /// 重置所有滑动状态
  void resetAll() {
    if (_currentSwipingComponent != null) {
      _currentSwipingComponent!.resetSwipe();
      _currentSwipingComponent = null;
    }
  }

  /// 获取当前正在滑动的组件
  SwipeableComponent? get currentSwipingComponent => _currentSwipingComponent;
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

  /// 获取组件标识符（用于调试）
  String get componentId;
}
