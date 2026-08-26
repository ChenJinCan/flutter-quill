import 'package:flutter_quill/src/document/nodes/block.dart';
import 'package:flutter_quill/src/document/nodes/line.dart';
import 'package:flutter_quill/src/document/nodes/node.dart';
import 'package:flutter_quill/src/editor/widgets/text/swipe_manager.dart';
import 'package:test/test.dart';

void main() {
  final manager = SwipeStateManager();

  tearDown(manager.resetAll);

  test('a second line swipe keeps exactly the newly swiped line selected', () {
    final first = _FakeSwipeableComponent('first', 0, 6);
    final second = _FakeSwipeableComponent('second', 6, 7);

    manager
      ..selectComponent(first, SwipeDirection.left)
      ..startSwipe(second, SwipeDirection.left, -40)
      ..selectComponent(second, SwipeDirection.left);

    expect(manager.getSelectedComponents(), {second});
    expect(manager.hasSelection, isTrue);
    expect(manager.isSelectionModeActive, isFalse);
    expect(first.selected, false);
    expect(second.selected, true);
  });

  test('selected ranges are returned in document order', () {
    final first = _FakeSwipeableComponent('first', 0, 6);
    final third = _FakeSwipeableComponent('third', 13, 6);

    manager
      ..selectComponent(first, SwipeDirection.left)
      ..toggleComponentSelection(third);

    expect(
      manager.selectedDocumentRanges,
      const [
        (offset: 0, length: 6),
        (offset: 13, length: 6),
      ],
    );
  });

  test('row selection controls toggle additional lines independently', () {
    final first = _FakeSwipeableComponent('first', 0, 6);
    final second = _FakeSwipeableComponent('second', 6, 7);

    manager
      ..selectComponent(first, SwipeDirection.left)
      ..enterSelectionMode()
      ..toggleComponentSelection(second);

    expect(manager.getSelectedComponents(), containsAll([first, second]));
    expect(first.selected, true);
    expect(second.selected, true);
    expect(manager.isSelectionModeActive, isTrue);

    manager.toggleComponentSelection(first);

    expect(manager.getSelectedComponents(), {second});
    expect(manager.isSelectionModeActive, isTrue);
    expect(first.selected, false);
    expect(second.selected, true);
  });

  test('explicit selection mode can be cancelled and clears selected rows', () {
    final first = _FakeSwipeableComponent('first', 0, 6);

    manager
      ..selectComponent(first, SwipeDirection.left)
      ..enterSelectionMode();

    expect(manager.isSelectionModeActive, isTrue);
    expect(manager.getSelectedComponents(), {first});

    manager.exitSelectionMode();

    expect(manager.isSelectionModeActive, isFalse);
    expect(manager.hasSelection, isFalse);
    expect(manager.getSelectedComponents(), isEmpty);
    expect(first.selected, isFalse);
  });
}

final class _FakeSwipeableComponent implements SwipeableComponent {
  _FakeSwipeableComponent(
      this.componentId, this.documentOffset, this.documentLength);

  @override
  final String componentId;
  @override
  final int documentOffset;
  @override
  final int documentLength;

  bool selected = false;
  final Line _line = Line();

  @override
  Node get documentNode => _line;
  @override
  Line get lineNode => _line;
  @override
  Block? get block => null;
  @override
  String get textContent => componentId;

  @override
  void setSelected(bool value) => selected = value;
  @override
  bool performSwipe(SwipeDirection direction, double offset) => true;
  @override
  void endSwipe() {}
  @override
  void resetSwipe() {}
  @override
  bool startDrag() => true;
  @override
  void endDrag() {}
}
