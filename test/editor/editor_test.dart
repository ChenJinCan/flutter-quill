import 'dart:convert' show jsonDecode;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill/quill_delta.dart';
import 'package:flutter_quill/src/l10n/extensions/localizations_ext.dart';
import 'package:flutter_quill_test/flutter_quill_test.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late QuillController controller;
  var didCopy = false;

  setUp(() {
    controller = QuillController.basic();
  });

  tearDown(() {
    controller.dispose();
  });

  group('QuillEditor', () {
    testWidgets(
      'tapping below long multi-line content places the caret at document end',
      (tester) async {
        controller.document.insert(
          0,
          'first line\nsecond line stays long across the editor',
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topCenter,
                child: QuillEditor.basic(
                  controller: controller,
                  config: const QuillEditorConfig(minHeight: 400),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final editorRect = tester.getRect(find.byType(QuillEditor));
        await tester.tapAt(
          Offset(editorRect.left + 80, editorRect.bottom - 24),
        );
        await tester.pump();

        expect(controller.selection.isCollapsed, isTrue);
        expect(
          controller.selection.extentOffset,
          controller.document.length - 1,
        );
      },
    );

    testWidgets(
      'double tapping trailing editor space keeps a collapsed end caret',
      (tester) async {
        const text = '提供给广告费';
        controller.document.insert(0, text);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuillEditor.basic(
                controller: controller,
                config: const QuillEditorConfig(expands: true),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final editorRect = tester.getRect(find.byType(QuillEditor));
        final trailingSpace = Offset(
          editorRect.right - 8,
          editorRect.top + 24,
        );
        await tester.tapAt(trailingSpace);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(trailingSpace);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          controller.selection,
          const TextSelection.collapsed(offset: text.length),
        );
      },
    );

    testWidgets(
      'double tapping internal whitespace keeps a caret and shows the menu',
      (tester) async {
        const text = 'left right';
        var menuButtonTypes = <ContextMenuButtonType>[];
        controller.document.insert(0, text);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(platform: TargetPlatform.iOS),
            home: Scaffold(
              body: QuillEditor.basic(
                controller: controller,
                config: QuillEditorConfig(
                  expands: true,
                  contextMenuBuilder: (_, state) {
                    menuButtonTypes = state.contextMenuButtonItems
                        .map((item) => item.type)
                        .toList();
                    return const SizedBox(
                      key: ValueKey('collapsed-caret-menu'),
                      width: 120,
                      height: 44,
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final lines = _editableTextLines(tester);
        expect(lines, hasLength(1));
        final line = lines.single;
        final whitespaceStart = line.getLocalRectForCaret(
          const TextPosition(offset: 4),
        );
        final whitespaceEnd = line.getLocalRectForCaret(
          const TextPosition(offset: 5),
        );
        final whitespaceCenter = line.localToGlobal(
          Offset(
            (whitespaceStart.left + whitespaceEnd.left) / 2,
            whitespaceStart.center.dy,
          ),
        );

        await tester.tapAt(whitespaceCenter);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(whitespaceCenter);
        await tester.pumpAndSettle();

        expect(controller.selection.isCollapsed, isTrue);
        expect(controller.selection.extentOffset, anyOf(4, 5));
        expect(find.byKey(const ValueKey('collapsed-caret-menu')), findsOne);
        expect(menuButtonTypes, contains(ContextMenuButtonType.cut));
        expect(menuButtonTypes, contains(ContextMenuButtonType.copy));
        expect(menuButtonTypes, contains(ContextMenuButtonType.paste));
        expect(menuButtonTypes, contains(ContextMenuButtonType.selectAll));
      },
    );

    testWidgets('double tapping a line tail does not select its final word', (
      tester,
    ) async {
      controller.document.insert(0, 'first\nsecond');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(expands: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lines = _editableTextLines(tester);
      expect(lines, hasLength(2));
      final firstLine = lines.first;
      final lineEndCaret = firstLine.getLocalRectForCaret(
        const TextPosition(offset: 5),
      );
      final lineTail = firstLine.localToGlobal(
        lineEndCaret.centerRight + const Offset(24, 0),
      );

      await tester.tapAt(lineTail);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(lineTail);
      await tester.pumpAndSettle();

      expect(controller.selection.isCollapsed, isTrue);
      expect(controller.selection.extentOffset, 5);
    });

    testWidgets('double tapping an empty paragraph keeps its empty-line caret',
        (
      tester,
    ) async {
      controller.document.insert(0, 'first\n\nthird');
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(expands: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lines = _editableTextLines(tester);
      expect(lines, hasLength(3));
      final emptyLine = lines[1];
      final emptyLineCaret = emptyLine.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final emptyLineSpace = emptyLine.localToGlobal(
        emptyLineCaret.centerRight + const Offset(24, 0),
      );

      await tester.tapAt(emptyLineSpace);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(emptyLineSpace);
      await tester.pumpAndSettle();

      expect(
        controller.selection,
        const TextSelection.collapsed(offset: 6),
      );
    });

    testWidgets('double tapping text still selects the tapped word', (
      tester,
    ) async {
      const text = 'double tap target';
      var menuButtonTypes = <ContextMenuButtonType>[];
      controller.document.insert(0, text);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: QuillEditor.basic(
              controller: controller,
              config: QuillEditorConfig(
                expands: true,
                contextMenuBuilder: (_, state) {
                  menuButtonTypes = state.contextMenuButtonItems
                      .map((item) => item.type)
                      .toList();
                  return const SizedBox(
                    key: ValueKey('word-selection-menu'),
                    width: 120,
                    height: 44,
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final lines = <RenderEditableTextLine>[];
      void collectLines(RenderObject child) {
        if (child is RenderEditableTextLine) lines.add(child);
        child.visitChildren(collectLines);
      }

      tester.renderObject(find.byType(QuillEditor)).visitChildren(collectLines);
      expect(lines, hasLength(1));
      final line = lines.single;
      final wordStart = line.getLocalRectForCaret(
        const TextPosition(offset: 0),
      );
      final wordEnd = line.getLocalRectForCaret(const TextPosition(offset: 6));
      final wordCenter = line.localToGlobal(
        Offset(
          (wordStart.left + wordEnd.left) / 2,
          wordStart.center.dy,
        ),
      );

      await tester.tapAt(wordCenter);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(wordCenter);
      await tester.pumpAndSettle();

      expect(controller.selection.isCollapsed, isFalse);
      expect(controller.selection.textInside(text), 'double');
      expect(find.byKey(const ValueKey('word-selection-menu')), findsOne);
      expect(menuButtonTypes, contains(ContextMenuButtonType.copy));
    });

    testWidgets(
      'row selection controls toggle another line without moving the caret',
      (tester) async {
        controller.document.insert(0, 'first line\nsecond line');
        controller.updateSelection(
          const TextSelection.collapsed(offset: 0),
          ChangeSource.silent,
        );
        final focusNode = FocusNode();
        final scrollController = ScrollController();
        addTearDown(focusNode.dispose);
        addTearDown(scrollController.dispose);
        final manager = SwipeStateManager();
        addTearDown(manager.resetAll);

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuillEditor(
                controller: controller,
                focusNode: focusNode,
                scrollController: scrollController,
                config: const QuillEditorConfig(
                  minHeight: 160,
                  padding: EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final lines = <RenderEditableTextLine>[];
        void collectLines(RenderObject child) {
          if (child is RenderEditableTextLine) lines.add(child);
          child.visitChildren(collectLines);
        }

        tester
            .renderObject(find.byType(QuillEditor))
            .visitChildren(collectLines);
        expect(lines, hasLength(2));
        manager
          ..selectComponent(lines.first, SwipeDirection.left)
          ..enterSelectionMode();
        await tester.pump();

        final second = lines.last;
        final semantics = SemanticsConfiguration();
        second.describeSemanticsConfiguration(semantics);
        expect(semantics.isSelected, isFalse);
        expect(semantics.onTap, isNotNull);
        final controlCenter = second.localToGlobal(
          Offset(second.size.width - 18, second.size.height / 2),
        );
        await tester.tapAt(controlCenter);
        await tester.pump();

        expect(manager.getSelectedComponents(), containsAll(lines));
        expect(second.swipeState.isSelected, isTrue);
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
        expect(focusNode.hasFocus, isFalse);

        final secondSwipeStart = second.localToGlobal(
          Offset(second.size.width * 0.7, second.size.height / 2),
        );
        await tester.dragFrom(secondSwipeStart, const Offset(-180, 0));
        await tester.pump(const Duration(milliseconds: 350));

        expect(manager.getSelectedComponents(), {second});
        expect(lines.first.swipeState.isSelected, isFalse);
        expect(controller.selection, const TextSelection.collapsed(offset: 0));
        expect(focusNode.hasFocus, isFalse);
      },
    );

    testWidgets('Keyboard entered text is stored in document', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor.basic(
            controller: controller,
            config: const QuillEditorConfig(),
          ),
        ),
      );
      await tester.quillEnterText(find.byType(QuillEditor), 'test\n');

      expect(controller.document.toPlainText(), 'test\n');
    });

    testWidgets(
      'keyboard Enter continues an indented ordered list with stable numbering',
      (tester) async {
        controller.dispose();
        const topItem = '一级列表';
        const nestedItem = '二级列表';
        const newNestedItem = '换行后的二级列表';
        const tailItem = '下一个一级列表';
        const nestedItemEnd = topItem.length + 1 + nestedItem.length;
        final replaceCalls = <(int, int, Object?)>[];
        controller = QuillController(
          document: Document.fromDelta(
            Delta()
              ..insert(topItem)
              ..insert('\n', <String, dynamic>{
                Attribute.list.key: Attribute.ol.value,
              })
              ..insert(nestedItem, <String, dynamic>{Attribute.bold.key: true})
              ..insert('\n', <String, dynamic>{
                Attribute.list.key: Attribute.ol.value,
                Attribute.indent.key: Attribute.indentL1.value,
              })
              ..insert(tailItem)
              ..insert('\n', <String, dynamic>{
                Attribute.list.key: Attribute.ol.value,
              }),
          ),
          selection: const TextSelection.collapsed(offset: nestedItemEnd),
          keepStyleOnNewLine: false,
          onReplaceText: (index, length, data) {
            replaceCalls.add((index, length, data));
            return true;
          },
        );

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: QuillEditor.basic(
                controller: controller,
                config: const QuillEditorConfig(),
              ),
            ),
          ),
        );
        final editor = find.byType(QuillEditor);

        await tester.quillEnterTextAtPosition(editor, '\n', nestedItemEnd);
        expect(replaceCalls, <(int, int, Object?)>[(nestedItemEnd, 0, '\n')]);
        final topLevelAttributes = <String, dynamic>{
          Attribute.list.key: Attribute.ol.value,
        };
        final listAttributes = <String, dynamic>{
          Attribute.list.key: Attribute.ol.value,
          Attribute.indent.key: Attribute.indentL1.value,
        };
        expect(
          controller.document.toDelta(),
          Delta()
            ..insert(topItem)
            ..insert('\n', topLevelAttributes)
            ..insert(
              nestedItem,
              <String, dynamic>{Attribute.bold.key: true},
            )
            ..insert('\n\n', listAttributes)
            ..insert(tailItem)
            ..insert('\n', topLevelAttributes),
        );
        await tester.quillEnterTextAtPosition(
          editor,
          newNestedItem,
          nestedItemEnd + 1,
        );
        await tester.pumpAndSettle();

        expect(
          controller.document.toDelta(),
          Delta()
            ..insert(topItem)
            ..insert('\n', topLevelAttributes)
            ..insert(
              nestedItem,
              <String, dynamic>{Attribute.bold.key: true},
            )
            ..insert('\n', listAttributes)
            ..insert(newNestedItem)
            ..insert('\n', listAttributes)
            ..insert(tailItem)
            ..insert('\n', topLevelAttributes),
        );
        final numberPoints = tester
            .widgetList<QuillNumberPoint>(find.byType(QuillNumberPoint))
            .toList();
        expect(numberPoints, hasLength(4));
        expect(
          numberPoints.map((point) => point.index),
          <String>['1', 'a', 'b', '2'],
        );
      },
    );

    testWidgets('insertContent is handled correctly', (tester) async {
      String? latestUri;
      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor(
            focusNode: FocusNode(),
            scrollController: ScrollController(),
            controller: controller,
            config: QuillEditorConfig(
              autoFocus: true,
              expands: true,
              contentInsertionConfiguration: ContentInsertionConfiguration(
                onContentInserted: (content) {
                  latestUri = content.uri;
                },
                allowedMimeTypes: <String>['image/gif'],
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(QuillEditor));
      await tester.quillEnterText(find.byType(QuillEditor), 'test\n');
      await tester.idle();

      const uri =
          'content://com.google.android.inputmethod.latin.fileprovider/test.gif';
      final messageBytes =
          const JSONMessageCodec().encodeMessage(<String, dynamic>{
        'args': <dynamic>[
          -1,
          'TextInputAction.commitContent',
          jsonDecode(
              '{"mimeType": "image/gif", "data": [0,1,0,1,0,1,0,0,0], "uri": "$uri"}'),
        ],
        'method': 'TextInputClient.performAction',
      });

      Object? error;
      try {
        await tester.binding.defaultBinaryMessenger
            .handlePlatformMessage('flutter/textinput', messageBytes, (_) {});
      } catch (e) {
        error = e;
      }
      expect(error, isNull);
      expect(latestUri, equals(uri));
    });

    Widget customBuilder(BuildContext context, QuillRawEditorState state) {
      return AdaptiveTextSelectionToolbar(
        anchors: state.contextMenuAnchors,
        children: [
          Container(
            height: 50,
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                IconButton(
                  onPressed: () {
                    didCopy = true;
                  },
                  icon: const Icon(Icons.copy),
                ),
              ],
            ),
          ),
        ],
      );
    }

    testWidgets('custom context menu builder', (tester) async {
      controller.document.insert(0, 'long press target');
      final focusNode = FocusNode();
      final scrollController = ScrollController();
      addTearDown(focusNode.dispose);
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: QuillEditor(
            focusNode: focusNode,
            scrollController: scrollController,
            controller: controller,
            config: QuillEditorConfig(
              autoFocus: true,
              expands: true,
              contextMenuBuilder: customBuilder,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);
      expect(controller.selection.isCollapsed, isTrue);

      // Long press to show menu
      await tester.longPress(find.byType(QuillEditor));
      await tester.pumpAndSettle();

      // Verify custom widget shows
      expect(find.byIcon(Icons.copy), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy));
      expect(didCopy, isTrue);
    });

    testWidgets(
      'QuillEditorOpenSearchAction should not throw an exception when the required localization delegates are provided',
      (tester) async {
        final editorFocusNode = FocusNode();
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            home: QuillEditor.basic(
              controller: controller,
              config: const QuillEditorConfig(),
              focusNode: editorFocusNode,
            ),
          ),
        );
        // Required, otherwise the action shortcuts won't be invoked.
        editorFocusNode.requestFocus();

        await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.control);

        await tester.pump();

        final exception = tester.takeException();
        expect(
          exception,
          isNot(
            isInstanceOf<MissingFlutterQuillLocalizationException>(),
          ),
        );

        expect(exception, isNull);
      },
    );

    testWidgets(
      'should throw MissingFlutterQuillLocalizationException if the delegate not provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Text(context.loc.font),
            ),
          ),
        );

        final exception = tester.takeException();

        expect(exception, isNotNull);
        expect(
          exception,
          isA<MissingFlutterQuillLocalizationException>(),
        );
      },
    );

    testWidgets(
      'should not throw MissingFlutterQuillLocalizationException if the delegate is provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates:
                FlutterQuillLocalizations.localizationsDelegates,
            home: Builder(
              builder: (context) => Text(context.loc.font),
            ),
          ),
        );

        final exception = tester.takeException();

        expect(exception, isNull);
        expect(
          exception,
          isNot(isA<MissingFlutterQuillLocalizationException>()),
        );
      },
    );

    testWidgets(
      'should throw MissingFlutterQuillLocalizationException if the delegate is not provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Text(context.loc.font),
            ),
          ),
        );

        final exception = tester.takeException();

        expect(exception, isNotNull);
        expect(
          exception,
          isA<MissingFlutterQuillLocalizationException>(),
        );
      },
    );
  });
}

List<RenderEditableTextLine> _editableTextLines(WidgetTester tester) {
  final lines = <RenderEditableTextLine>[];

  void collectLines(RenderObject child) {
    if (child is RenderEditableTextLine) lines.add(child);
    child.visitChildren(collectLines);
  }

  tester.renderObject(find.byType(QuillEditor)).visitChildren(collectLines);
  return lines;
}
