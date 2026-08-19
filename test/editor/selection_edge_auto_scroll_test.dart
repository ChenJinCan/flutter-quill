import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'selection handle edge drag keeps outer scrolling gradual',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final body = List.generate(
        80,
        (index) => 'Line ${index + 1} keeps selection scrolling predictable',
      ).join('\n');
      final controller = QuillController(
        document: Document()..insert(0, body),
        selection: const TextSelection(baseOffset: 0, extentOffset: 52),
      );
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                QuillEditor(
                  controller: controller,
                  focusNode: focusNode,
                  scrollController: scrollController,
                  config: const QuillEditorConfig(
                    autoFocus: true,
                    scrollable: false,
                    minHeight: 1200,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final handleGestures = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onPanStart != null &&
            widget.onPanUpdate != null &&
            widget.onPanEnd != null,
        description: 'draggable selection handles',
      );
      expect(handleGestures, findsNWidgets(2));

      final lowerHandle = handleGestures.at(1);
      final viewport = tester.getRect(find.byType(ListView));
      final gesture = await tester.startGesture(tester.getCenter(lowerHandle));
      await gesture.moveTo(Offset(
        tester.getCenter(lowerHandle).dx,
        viewport.bottom + 8,
      ));
      await tester.pump(const Duration(milliseconds: 16));

      for (var index = 0; index < 8; index++) {
        await gesture.moveBy(const Offset(0, 1));
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(
        scrollController.offset,
        lessThanOrEqualTo(32),
        reason: 'A near-edge drag must not skip several lines in 144ms.',
      );

      final offsetAfterDelay = scrollController.offset;
      final selectionAfterDelay = controller.selection.extentOffset;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scrollController.offset, greaterThan(offsetAfterDelay));
      expect(scrollController.offset, lessThanOrEqualTo(120));
      expect(
          controller.selection.extentOffset, greaterThan(selectionAfterDelay));

      await gesture.moveTo(Offset(
        tester.getCenter(lowerHandle).dx,
        viewport.bottom - 80,
      ));
      await tester.pump(const Duration(milliseconds: 32));
      final offsetAfterLeavingEdge = scrollController.offset;
      await tester.pump(const Duration(milliseconds: 300));
      expect(scrollController.offset, offsetAfterLeavingEdge);

      await gesture.up();
      await tester.pump();
    },
  );

  testWidgets(
    'selection handle upper-edge drag keeps outer scrolling gradual',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final body = List.generate(
        80,
        (index) => 'Line ${index + 1} keeps selection scrolling predictable',
      ).join('\n');
      final controller = QuillController(
        document: Document()..insert(0, body),
        selection: const TextSelection(baseOffset: 870, extentOffset: 986),
      );
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                QuillEditor(
                  controller: controller,
                  focusNode: focusNode,
                  scrollController: scrollController,
                  config: const QuillEditorConfig(
                    autoFocus: true,
                    scrollable: false,
                    minHeight: 1200,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      scrollController.jumpTo(600);
      await tester.pump();
      final viewport = tester.getRect(find.byType(ListView));

      final handleGestures = find.byWidgetPredicate(
        (widget) =>
            widget is GestureDetector &&
            widget.onPanStart != null &&
            widget.onPanUpdate != null &&
            widget.onPanEnd != null,
        description: 'draggable selection handles',
      );
      expect(handleGestures, findsNWidgets(2));

      final upperHandle = handleGestures.first;
      final initialOffset = scrollController.offset;
      final gesture = await tester.startGesture(tester.getCenter(upperHandle));
      await gesture.moveTo(Offset(
        tester.getCenter(upperHandle).dx,
        viewport.top - 8,
      ));
      await tester.pump(const Duration(milliseconds: 16));
      for (var index = 0; index < 8; index++) {
        await gesture.moveBy(const Offset(0, -1));
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(initialOffset - scrollController.offset, lessThanOrEqualTo(32));
      final offsetAfterDelay = scrollController.offset;
      for (var frame = 0; frame < 60; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(scrollController.offset, lessThan(offsetAfterDelay));
      expect(
        offsetAfterDelay - scrollController.offset,
        lessThanOrEqualTo(120),
      );

      await gesture.up();
      await tester.pump();
    },
  );
}
