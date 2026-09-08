import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final focused in [true, false]) {
    testWidgets('focus-suppressed edits repaint with focus=$focused',
        (tester) async {
      final controller = QuillController.basic();
      final focus = FocusNode();
      final scroll = ScrollController();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      addTearDown(scroll.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: QuillEditor(
            controller: controller,
            focusNode: focus,
            scrollController: scroll,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      if (focused) {
        focus.requestFocus();
        await tester.pump();
      }
      controller
        ..ignoreFocusOnTextChange = true
        ..skipRequestKeyboard = true
        ..compose(
          Delta()..insert('Visible immediately'),
          const TextSelection.collapsed(offset: 19),
          ChangeSource.local,
        );
      await tester.pump();
      final visibleText = find.byWidgetPredicate((widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Visible immediately'));
      expect(visibleText, findsOneWidget);
      expect(focus.hasFocus, focused);
      controller.undo();
      await tester.pump();
      expect(visibleText, findsNothing);
      expect(focus.hasFocus, focused);
      controller.redo();
      await tester.pump();
      expect(visibleText, findsOneWidget);
      expect(focus.hasFocus, focused);
      if (focused) {
        // A toolbar may release focus while the new document still awaits its
        // render frame. That pending rebuild must not reacquire the keyboard.
        controller.compose(
          Delta()..insert('Updated '),
          const TextSelection.collapsed(offset: 27),
          ChangeSource.local,
        );
        focus.canRequestFocus = false;
        controller
          ..ignoreFocusOnTextChange = false
          ..skipRequestKeyboard = false;
        await tester.pump();
        focus.canRequestFocus = true;
        await tester.pump();
        expect(focus.hasFocus, isFalse);
        expect(tester.testTextInput.isVisible, isFalse);
        expect(visibleText, findsOneWidget);
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
