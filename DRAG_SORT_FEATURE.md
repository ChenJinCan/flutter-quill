# Flutter Quill 长按拖拽排序功能

本文档介绍了为 Flutter Quill 编辑器实现的长按 TextLine 进行 Document 拖拽排序功能，类似 Notion 的操作方式。

## 功能概述

### 核心功能
- **长按检测**: 在 TextLine 上长按 500ms 触发拖拽模式
- **拖拽排序**: 长按后可以拖拽 TextLine 到不同位置重新排序
- **视觉反馈**: 拖拽过程中显示预览和插入位置指示器
- **文档重排序**: 自动更新 QuillController 中的文档结构
- **基于 RenderObject**: 在 RenderObject 层面实现，性能优良

### 滑动功能（已有功能的扩展）
- **水平滑动**: 支持左滑/右滑手势
- **选中状态**: 滑动后显示选中效果
- **状态管理**: 全局管理确保一次只能操作一个组件

## 技术架构

### 核心文件结构

```
lib/src/editor/widgets/text/
├── swipe_manager.dart          # 全局滑动和拖拽状态管理
├── drag_sort_overlay.dart      # 拖拽排序覆盖层
├── text_line.dart             # TextLine 组件（已扩展）
└── text_block.dart            # TextBlock 组件（已扩展）
```

### 关键类说明

#### 1. SwipeStateManager (全局状态管理器)
```dart
class SwipeStateManager {
  // 滑动状态管理
  bool startSwipe(SwipeableComponent component, SwipeDirection direction, double offset);
  void endSwipe(SwipeableComponent component);
  void selectComponent(SwipeableComponent component, SwipeDirection direction);
  
  // 拖拽状态管理
  bool startDrag(SwipeableComponent component);
  void updateDrag(Offset globalPosition);
  void endDrag();
  
  // 回调设置
  void setSwipeCallbacks({...});
  void setDragCallbacks({...});
}
```

#### 2. SwipeableComponent (可操作组件接口)
```dart
abstract class SwipeableComponent {
  // 滑动相关
  bool performSwipe(SwipeDirection direction, double offset);
  void endSwipe();
  void resetSwipe();
  void setSelected(bool selected);
  
  // 拖拽相关
  bool startDrag();
  void endDrag();
  
  // 组件信息
  String get componentId;
  String get textContent;
  Node get documentNode;
  int get documentOffset;
  int get documentLength;
}
```

#### 3. DragSortOverlay (拖拽覆盖层)
```dart
class DragSortOverlay {
  static void show({
    required BuildContext context,
    required SwipeableComponent component,
    required QuillController controller,
    required GlobalKey editorKey,
    required Offset initialGlobalPosition,
  });
  
  static void hide();
  static void updatePosition(Offset globalPosition);
}
```

## 使用方法

### 1. 基本设置

在 `QuillRawEditorState` 的 `initState` 中设置回调：

```dart
void _setupDragSortCallbacks() {
  final swipeManager = SwipeStateManager();
  
  // 设置拖拽回调
  swipeManager.setDragCallbacks(
    onDragStart: () {
      debugPrint('拖拽排序开始');
    },
    onDragUpdate: (globalPosition, draggingComponent) {
      // 显示拖拽覆盖层
      DragSortOverlay.show(
        context: context,
        component: draggingComponent,
        controller: controller,
        editorKey: _editorKey,
        initialGlobalPosition: globalPosition,
      );
    },
    onDragEnd: (draggingComponent) {
      DragSortOverlay.hide();
      debugPrint('拖拽排序结束');
    },
  );

  // 设置滑动回调
  swipeManager.setSwipeCallbacks(
    onComponentSelected: (line, block, direction) {
      // 处理组件选中事件
      _showCustomDialog(line, block, direction);
    },
  );
}
```

### 2. 用户操作流程

#### 长按拖拽排序
1. 用户在 TextLine 上长按 500ms
2. 进入拖拽模式，显示拖拽预览
3. 用户拖拽到目标位置
4. 松开手指，自动重排序文档

#### 水平滑动
1. 用户在 TextLine 上水平滑动
2. 超过阈值时显示滑动效果
3. 松开手指后显示选中状态
4. 触发自定义操作回调

### 3. 自定义操作示例

```dart
void _handleComponentSelected(SwipeableComponent component, SwipeDirection direction) {
  if (direction == SwipeDirection.left) {
    // 左滑操作：删除行
    final offset = component.documentOffset;
    final length = component.documentLength;
    controller.document.delete(offset, length);
  } else {
    // 右滑操作：复制行
    final text = component.textContent;
    final insertOffset = component.documentOffset + component.documentLength;
    controller.document.insert(insertOffset, '\n$text');
  }
}
```

## 实现细节

### 长按检测机制

在 `RenderEditableTextLine.handleEvent` 中实现：

```dart
if (event is PointerDownEvent) {
  _startLongPressDetection(event.localPosition);
} else if (event is PointerMoveEvent && _totalDragDistance > 10) {
  if (_isLongPressing) {
    _startDragging(event.localPosition);
  }
}
```

### 拖拽预览组件

```dart
Widget _createDragPreview(SwipeableComponent component) {
  return Container(
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
      children: [
        const Icon(Icons.drag_handle),
        Text(component.textContent),
      ],
    ),
  );
}
```

### 文档重排序逻辑

```dart
void _reorderDocumentNode(Node draggingNode, int fromOffset, int length, int toOffset) {
  // 1. 获取要移动的文本内容
  final text = controller.document.toPlainText().substring(fromOffset, fromOffset + length);
  
  // 2. 删除原位置的内容
  controller.document.delete(fromOffset, length);
  
  // 3. 调整目标位置
  int adjustedToOffset = toOffset > fromOffset ? toOffset - length : toOffset;
  
  // 4. 在新位置插入内容
  controller.document.insert(adjustedToOffset, text);
  
  // 5. 更新选择位置
  controller.updateSelection(
    TextSelection.collapsed(offset: adjustedToOffset),
    ChangeSource.local,
  );
}
```

## 视觉效果

### 选中状态效果
- 蓝色背景高亮：`Color(0xFF2196F3).withOpacity(0.2)`
- 圆角边框：`BorderRadius.circular(4.0)`
- 左右 padding：`2px`

### 滑动指示器
- 左滑：红色指示器 `Color(0xFFF44336)`
- 右滑：绿色指示器 `Color(0xFF4CAF50)`
- 透明度：`0.3`
- 宽度：`4px`

### 拖拽预览
- 白色背景，圆角 `8px`
- 阴影效果：`blur: 8px, offset: (0, 4)`
- 缩放动画：`scale: 1.05`

## 性能优化

1. **单例模式**: `SwipeStateManager` 使用单例模式避免重复实例化
2. **状态管理**: 确保一次只能有一个组件处于操作状态
3. **及时清理**: 操作结束后及时清理状态和监听器
4. **RenderObject 层实现**: 避免不必要的 Widget 重建

## 扩展性

### 支持自定义操作
通过回调机制可以轻松添加自定义操作：

```dart
swipeManager.setSwipeCallbacks(
  onComponentSelected: (line, block, direction) {
    // 自定义操作逻辑
    switch (direction) {
      case SwipeDirection.left:
        customLeftAction(line ?? block);
        break;
      case SwipeDirection.right:
        customRightAction(line ?? block);
        break;
    }
  },
);
```

### 支持不同组件类型
- **TextLine**: 单行文本操作
- **TextBlock**: 多行文本块操作
- **自定义组件**: 实现 `SwipeableComponent` 接口即可支持

## 兼容性

- **Flutter 版本**: >= 3.0.0
- **平台支持**: iOS, Android, Web, Desktop
- **现有功能**: 完全兼容现有的 Flutter Quill 功能

## 总结

这个长按拖拽排序功能为 Flutter Quill 编辑器带来了类似 Notion 的强大交互体验，同时保持了良好的性能和扩展性。通过在 RenderObject 层面实现，确保了功能的高效性和稳定性。

用户可以通过简单的长按和滑动手势来重新组织文档内容，大大提升了编辑体验。同时，开发者可以通过丰富的回调机制来实现各种自定义操作。 