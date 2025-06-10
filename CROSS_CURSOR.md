diff --git a/lib/src/editor/editor.dart b/lib/src/editor/editor.dart
index d5b6f746..f6772d55 100644
--- a/lib/src/editor/editor.dart
+++ b/lib/src/editor/editor.dart
@@ -635,12 +635,9 @@ class _QuillEditorSelectionGestureDetectorBuilder
         platform: platform,
         supportWeb: true,
       )) {
-        renderEditor!.selectPositionAt(
-          from: details.globalPosition,
-          cause: SelectionChangedCause.longPress,
-        );
+        _handleLongPressSelection(details.globalPosition);
       } else {
-        renderEditor!.selectWord(SelectionChangedCause.longPress);
+        _handleLongPressSelection(details.globalPosition);
         Feedback.forLongPress(_state.context);
       }
     }
@@ -648,6 +645,89 @@ class _QuillEditorSelectionGestureDetectorBuilder
     _showMagnifierIfSupportedByPlatform(details.globalPosition);
   }
 
+  /// Handles long press selection with smart word selection fallback
+  void _handleLongPressSelection(Offset globalPosition) {
+    // First try to select word at the current position
+    final position = renderEditor!.getPositionForOffset(globalPosition);
+    final wordSelection = renderEditor!.selectWordAtPosition(position);
+
+    // Check if we got a valid word selection
+    final selectedText =
+        wordSelection.textInside(_state.controller.document.toPlainText());
+    final hasValidSelection = !wordSelection.isCollapsed &&
+        selectedText.trim().isNotEmpty &&
+        selectedText.trim() != '\n';
+
+    if (hasValidSelection) {
+      // We found a valid word at the current position
+      renderEditor!._handleSelectionChange(
+          wordSelection, SelectionChangedCause.longPress);
+    } else {
+      // No valid word at current position, try to find nearby word
+      _selectNearbyWordOnLongPress(globalPosition);
+    }
+  }
+
+  /// Attempts to select a word near the given position when long press
+  /// didn't select any meaningful text
+  void _selectNearbyWordOnLongPress(Offset globalPosition) {
+    final position = renderEditor!.getPositionForOffset(globalPosition);
+    final documentText = _state.controller.document.toPlainText();
+
+    // Search for words in both directions from the current position
+    final searchRadius = 20; // Search within 20 characters
+
+    for (int radius = 1; radius <= searchRadius; radius++) {
+      // Try positions before the current position
+      final beforeOffset =
+          (position.offset - radius).clamp(0, documentText.length);
+      if (beforeOffset != position.offset) {
+        final beforePosition = TextPosition(offset: beforeOffset);
+        final beforeWord = renderEditor!.selectWordAtPosition(beforePosition);
+        final beforeText = beforeWord.textInside(documentText);
+
+        if (!beforeWord.isCollapsed &&
+            beforeText.trim().isNotEmpty &&
+            beforeText.trim() != '\n' &&
+            _isValidWord(beforeText)) {
+          renderEditor!._handleSelectionChange(
+              beforeWord, SelectionChangedCause.longPress);
+          return;
+        }
+      }
+
+      // Try positions after the current position
+      final afterOffset =
+          (position.offset + radius).clamp(0, documentText.length);
+      if (afterOffset != position.offset) {
+        final afterPosition = TextPosition(offset: afterOffset);
+        final afterWord = renderEditor!.selectWordAtPosition(afterPosition);
+        final afterText = afterWord.textInside(documentText);
+
+        if (!afterWord.isCollapsed &&
+            afterText.trim().isNotEmpty &&
+            afterText.trim() != '\n' &&
+            _isValidWord(afterText)) {
+          renderEditor!._handleSelectionChange(
+              afterWord, SelectionChangedCause.longPress);
+          return;
+        }
+      }
+    }
+
+    // If no nearby word found, just place cursor at the current position
+    renderEditor!.selectPositionAt(
+      from: globalPosition,
+      cause: SelectionChangedCause.longPress,
+    );
+  }
+
+  /// Checks if the given text represents a valid word (contains letters or numbers)
+  bool _isValidWord(String text) {
+    // Check if text contains at least one alphanumeric character
+    return RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5]').hasMatch(text);
+  }
+
   @override
   void onSingleLongTapEnd(LongPressEndDetails details) {
     if (_state.configurations.onSingleLongTapEnd != null) {
diff --git a/lib/src/editor/widgets/delegate.dart b/lib/src/editor/widgets/delegate.dart
index 25b73bbc..d3f1471c 100644
--- a/lib/src/editor/widgets/delegate.dart
+++ b/lib/src/editor/widgets/delegate.dart
@@ -522,14 +522,25 @@ class EditorTextSelectionGestureDetectorBuilder {
   @protected
   void onDoubleTapDown(TapDragDownDetails details) {
     if (delegate.selectionEnabled) {
+      // First try to select the word at the current position
       renderEditor!.selectWord(SelectionChangedCause.tap);
-      // allow the selection to get updated before trying to bring up
-      // toolbars.
-      //
-      // if double tap happens on an editor that doesn't
-      // have focus, selection hasn't been set when the toolbars
-      // get added
+
+      // Check if we actually selected any text
       SchedulerBinding.instance.addPostFrameCallback((_) {
+        final selection = renderEditor?.selection;
+        final hasValidSelection = selection != null &&
+            !selection.isCollapsed &&
+            selection.isValid &&
+            editor!.textEditingValue.selection
+                .textInside(editor!.textEditingValue.text)
+                .trim()
+                .isNotEmpty;
+
+        if (!hasValidSelection) {
+          // If no valid text was selected, try to find and select a nearby word
+          _selectNearbyWord(details.globalPosition);
+        }
+
         if (checkSelectionToolbarShouldShow(isAdditionalAction: false)) {
           editor!.showToolbar();
         }
@@ -537,6 +548,79 @@ class EditorTextSelectionGestureDetectorBuilder {
     }
   }
 
+  /// Attempts to select a word near the given position when the initial
+  /// double-tap didn't select any meaningful text
+  void _selectNearbyWord(Offset globalPosition) {
+    final position = renderEditor!.getPositionForOffset(globalPosition);
+    final text = editor!.textEditingValue.text;
+
+    if (text.isEmpty) return;
+
+    // Search for the nearest word character within a reasonable range
+    const maxSearchDistance =
+        10; // Maximum characters to search in each direction
+
+    // First, try searching to the right
+    for (int i = 1;
+        i <= maxSearchDistance && position.offset + i < text.length;
+        i++) {
+      final newOffset = position.offset + i;
+      final char = text[newOffset];
+      if (_isWordCharacter(char)) {
+        final newPosition = TextPosition(offset: newOffset);
+        final wordBoundary = renderEditor!.getWordBoundary(newPosition);
+        if (wordBoundary.isValid && !wordBoundary.isCollapsed) {
+          final wordText = text.substring(wordBoundary.start, wordBoundary.end);
+          if (wordText.trim().isNotEmpty) {
+            renderEditor!.onSelectionChanged(
+              TextSelection(
+                  baseOffset: wordBoundary.start,
+                  extentOffset: wordBoundary.end),
+              SelectionChangedCause.tap,
+            );
+            return;
+          }
+        }
+      }
+    }
+
+    // If no word found to the right, try searching to the left
+    for (int i = 1; i <= maxSearchDistance && position.offset - i >= 0; i++) {
+      final newOffset = position.offset - i;
+      final char = text[newOffset];
+      if (_isWordCharacter(char)) {
+        final newPosition = TextPosition(offset: newOffset);
+        final wordBoundary = renderEditor!.getWordBoundary(newPosition);
+        if (wordBoundary.isValid && !wordBoundary.isCollapsed) {
+          final wordText = text.substring(wordBoundary.start, wordBoundary.end);
+          if (wordText.trim().isNotEmpty) {
+            renderEditor!.onSelectionChanged(
+              TextSelection(
+                  baseOffset: wordBoundary.start,
+                  extentOffset: wordBoundary.end),
+              SelectionChangedCause.tap,
+            );
+            return;
+          }
+        }
+      }
+    }
+  }
+
+  /// Checks if a character is part of a word (letter, digit, or underscore)
+  bool _isWordCharacter(String char) {
+    if (char.isEmpty) return false;
+    final codeUnit = char.codeUnitAt(0);
+    return (codeUnit >= 65 && codeUnit <= 90) || // A-Z
+        (codeUnit >= 97 && codeUnit <= 122) || // a-z
+        (codeUnit >= 48 && codeUnit <= 57) || // 0-9
+        codeUnit == 95 || // _
+        codeUnit >= 0x4e00 && codeUnit <= 0x9fff || // Chinese characters
+        codeUnit >= 0x3040 && codeUnit <= 0x309f || // Hiragana
+        codeUnit >= 0x30a0 && codeUnit <= 0x30ff || // Katakana
+        codeUnit >= 0xac00 && codeUnit <= 0xd7af; // Korean
+  }
+
   // Selects the set of paragraphs in a document that intersect a given range of
   // global positions.
   void _selectParagraphsInRange(
diff --git a/lib/src/editor/widgets/text/text_selection.dart b/lib/src/editor/widgets/text/text_selection.dart
index 5d5655b0..2ab9c296 100644
--- a/lib/src/editor/widgets/text/text_selection.dart
+++ b/lib/src/editor/widgets/text/text_selection.dart
@@ -517,11 +517,16 @@ class EditorTextSelectionOverlay {
       renderEditable.getLocalRectForCaret(positionAtEndOfLine).bottomCenter,
     );
 
+    // 向上调整放大镜位置，减少8像素的垂直偏移
+    const magnifierVerticalOffset = Offset(0, -8);
+
     return MagnifierInfo(
       fieldBounds: globalRenderEditableTopLeft & renderEditable.size,
       globalGesturePosition: globalGesturePosition,
-      caretRect: localCaretRect.shift(globalRenderEditableTopLeft),
-      currentLineBoundaries: lineBoundaries.shift(globalRenderEditableTopLeft),
+      caretRect: localCaretRect
+          .shift(globalRenderEditableTopLeft + magnifierVerticalOffset),
+      currentLineBoundaries: lineBoundaries
+          .shift(globalRenderEditableTopLeft + magnifierVerticalOffset),
     );
   }
 }
@@ -650,9 +655,14 @@ class _TextSelectionHandleOverlayState
 
   void _handleDragUpdate(DragUpdateDetails details) {
     if (!widget.renderObject.attached) return;
+
+    // 更新拖拽位置，提供更平滑的拖拽体验
     _dragPosition += details.delta;
+
+    // 使用全局位置而不是本地偏移计算，提高精确度
     final position =
         widget.renderObject.getPositionForOffset(details.globalPosition);
+
     if (widget.selection.isCollapsed) {
       widget.onSelectionHandleChanged(TextSelection.fromPosition(position));
       return;
@@ -679,8 +689,20 @@ class _TextSelectionHandleOverlayState
         throw ArgumentError('Invalid widget.position');
     }
 
-    // 防止在拖拽过程中创建collapsed selection，这会导致handles消失
+    // 防止在拖拽过程中创建collapsed selection，但允许短暂的重叠
+    // 这样可以避免手柄在交叉时突然消失
     if (newSelection.isCollapsed) {
+      // 如果选择变为collapsed，我们仍然允许更新，
+      // 但会在下一帧中调整为合理的选择
+      final minimalSelection = TextSelection(
+        baseOffset: newSelection.baseOffset,
+        extentOffset: newSelection.baseOffset + 1,
+      );
+      // 确保不超出文档范围
+      final documentLength = widget.renderObject.document.length;
+      if (minimalSelection.extentOffset <= documentLength) {
+        widget.onSelectionHandleChanged(minimalSelection);
+      }
       return;
     }
 
@@ -759,11 +781,20 @@ class _TextSelectionHandleOverlayState
       handleSize.height,
     );
 
-    // Make sure the GestureDetector is big enough to be easily interactive.
+    // 大幅增大手柄的交互区域，提高响应性
+    // 将最小触摸半径从 kMinInteractiveDimension / 2 增加到 30.0
+    // 同时确保交互区域至少是原始手柄大小的 2.5 倍
+    const enhancedTouchRadius = 30.0;
+    final minEnhancedSize = math.max(handleSize.width, handleSize.height) * 2.5;
+    final effectiveRadius = math.max(enhancedTouchRadius, minEnhancedSize / 2);
+
     final interactiveRect = handleRect.expandToInclude(
       Rect.fromCircle(
-          center: handleRect.center, radius: kMinInteractiveDimension / 2),
+        center: handleRect.center,
+        radius: effectiveRadius,
+      ),
     );
+
     final padding = RelativeRect.fromLTRB(
       math.max((interactiveRect.width - handleRect.width) / 2, 0),
       math.max((interactiveRect.height - handleRect.height) / 2, 0),
@@ -782,8 +813,10 @@ class _TextSelectionHandleOverlayState
           width: interactiveRect.width,
           height: interactiveRect.height,
           child: GestureDetector(
-            behavior: HitTestBehavior.translucent,
-            dragStartBehavior: widget.dragStartBehavior,
+            // 使用 opaque 行为确保手势能被可靠捕获
+            behavior: HitTestBehavior.opaque,
+            // 设置为 down 以提高响应速度
+            dragStartBehavior: DragStartBehavior.down,
             onPanStart: _handleDragStart,
             onPanUpdate: _handleDragUpdate,
             onPanEnd: _handleDragEnd,
