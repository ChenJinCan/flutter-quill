import 'package:flutter_quill/src/document/nodes/block.dart';
import 'package:flutter_quill/src/document/nodes/line.dart';
import 'package:flutter_quill/src/document/nodes/node.dart';
import 'package:flutter_quill/src/editor/widgets/text/swipe_manager.dart';
import 'package:test/test.dart';

void main() {
  final manager = SwipeStateManager();

  tearDown(manager.resetAll);

  test('a second line swipe preserves the existing multi-selection', () {
    final first = _FakeSwipeableComponent('first', 0, 6);
    final second = _FakeSwipeableComponent('second', 6, 7);

    manager
      ..selectComponent(first, SwipeDirection.left)
      ..startSwipe(second, SwipeDirection.left, -40)
      ..selectComponent(second, SwipeDirection.left);

    expect(manager.getSelectedComponents(), containsAll([first, second]));
    expect(first.selected, true);
    expect(second.selected, true);
  });

  test('selected ranges are returned in document order', () {
    final first = _FakeSwipeableComponent('first', 0, 6);
    final third = _FakeSwipeableComponent('third', 13, 6);

    manager
      ..selectComponent(third, SwipeDirection.left)
      ..selectComponent(first, SwipeDirection.left);

    expect(
      manager.selectedDocumentRanges,
      const [
        (offset: 0, length: 6),
        (offset: 13, length: 6),
      ],
    );
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
