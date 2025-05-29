import 'dart:convert';
import 'dart:io' as io show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill_example/quill_delta_sample.dart';
import 'package:flutter_quill_extensions/flutter_quill_extensions.dart';
import 'package:path/path.dart' as path;

// Define SwipeDirection enum and SwipeStateManager for demo
enum SwipeDirection { left, right }

// Mock SwipeStateManager for now
class SwipeStateManager {
  static final SwipeStateManager _instance = SwipeStateManager._internal();
  factory SwipeStateManager() => _instance;
  SwipeStateManager._internal();

  void clearSelection() {
    // Mock implementation
    print('清除选中状态');
  }
}

void main() => runApp(const MainApp());

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.light(useMaterial3: true),
      darkTheme: ThemeData.dark(useMaterial3: true),
      themeMode: ThemeMode.system,
      home: HomePage(),
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final QuillController _controller = () {
    return QuillController.basic(
        config: QuillControllerConfig(
      clipboardConfig: QuillClipboardConfig(
        enableExternalRichPaste: true,
        onImagePaste: (imageBytes) async {
          if (kIsWeb) {
            // Dart IO is unsupported on the web.
            return null;
          }
          // Save the image somewhere and return the image URL that will be
          // stored in the Quill Delta JSON (the document).
          final newFileName =
              'image-file-${DateTime.now().toIso8601String()}.png';
          final newPath = path.join(
            io.Directory.systemTemp.path,
            newFileName,
          );
          final file = await io.File(
            newPath,
          ).writeAsBytes(imageBytes, flush: true);
          return file.path;
        },
      ),
    ));
  }();
  final FocusNode _editorFocusNode = FocusNode();
  final ScrollController _editorScrollController = ScrollController();

  // 添加一个GlobalKey来访问QuillEditorState
  final GlobalKey<QuillEditorState> _editorKey = GlobalKey<QuillEditorState>();

  @override
  void initState() {
    super.initState();
    // Load document
    _controller.document = Document.fromJson(kQuillDefaultSample);
    // 添加一些示例内容来测试滑动功能
    _controller.document.insert(0, 'Line 1: 试试向左滑动这一行\n');
    _controller.document
        .insert(_controller.document.length - 1, 'Line 2: 试试向右滑动这一行\n');
    _controller.document
        .insert(_controller.document.length - 1, 'Line 3: 只能同时滑动一行\n');
    _controller.document
        .insert(_controller.document.length - 1, 'Line 4: 其他行会自动复原\n');
    _controller.document
        .insert(_controller.document.length - 1, '\nBlock 1: 试试滑动这个文本块\n\n');
    _controller.document
        .insert(_controller.document.length - 1, 'Block 2: 另一个可滑动的文本块\n');
  }

  void _handleSwipeStart() {
    print('滑动开始');
  }

  void _handleSwipeEnd() {
    print('滑动结束');
  }

  void _handleComponentSelected(
      Line? line, Block? block, SwipeDirection direction) {
    final component = line ?? block;
    if (component == null) return;

    final componentId = line != null
        ? 'TextLine-${line.documentOffset}'
        : 'TextBlock-${block!.documentOffset}';
    final textContent = component.toPlainText();
    final documentOffset = component.documentOffset;
    final documentLength = component.length;

    print(
        '组件选中: $componentId - 方向: ${direction == SwipeDirection.left ? '左滑' : '右滑'}');
    print('内容: $textContent');
    print('文档偏移: $documentOffset, 长度: $documentLength');

    // 根据组件类型获取不同的节点信息
    if (line != null) {
      print('这是一个TextLine组件，Line节点: ${line.runtimeType}');
    } else if (block != null) {
      print('这是一个TextBlock组件，Block节点: ${block.runtimeType}');
    }

    // 在这里你可以显示自定义弹窗
    _showCustomDialog(component, direction);
  }

  void _showCustomDialog(Node component, SwipeDirection direction) {
    final componentId = component is Line
        ? 'TextLine-${component.documentOffset}'
        : 'TextBlock-${component.documentOffset}';
    final textContent = component.toPlainText();
    final documentOffset = component.documentOffset;
    final documentLength = component.length;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Icon(
                direction == SwipeDirection.left
                    ? Icons.arrow_back
                    : Icons.arrow_forward,
                color: direction == SwipeDirection.left
                    ? Colors.red
                    : Colors.green,
              ),
              const SizedBox(width: 8),
              Text('${direction == SwipeDirection.left ? '左滑' : '右滑'}操作'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('组件: $componentId'),
              const SizedBox(height: 8),
              Text('内容: $textContent'),
              const SizedBox(height: 8),
              Text('文档偏移: $documentOffset'),
              const SizedBox(height: 8),
              Text('文档长度: $documentLength'),
              const SizedBox(height: 8),
              if (component is Line)
                Text('类型: TextLine')
              else if (component is Block)
                Text('类型: TextBlock'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 关闭弹窗时清除选中状态
                SwipeStateManager().clearSelection();
              },
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                // 使用QuillController进行操作示例
                _performControllerOperation(component, direction);
                // 清除选中状态
                SwipeStateManager().clearSelection();
              },
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
  }

  /// 使用QuillController对选中的组件进行操作的示例
  void _performControllerOperation(Node component, SwipeDirection direction) {
    print('执行${direction == SwipeDirection.left ? '左滑' : '右滑'}操作');

    if (direction == SwipeDirection.left) {
      // 左滑操作示例：在组件后面插入文本
      final insertOffset = component.documentOffset + component.length;
      _controller.document.insert(insertOffset, ' [已左滑]');
      print('在位置 $insertOffset 插入了 "[已左滑]" 文本');
    } else {
      // 右滑操作示例：在组件前面插入文本
      final insertOffset = component.documentOffset;
      _controller.document.insert(insertOffset, '[已右滑] ');
      print('在位置 $insertOffset 插入了 "[已右滑] " 文本');
    }

    // 你还可以做其他操作，比如：
    // - 删除组件：_controller.document.delete(component.documentOffset, component.documentLength);
    // - 格式化文本：_controller.formatText(component.documentOffset, component.documentLength, Attribute.bold);
    // - 移动光标：_controller.updateSelection(TextSelection.collapsed(offset: component.documentOffset), ChangeSource.local);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Flutter Quill Example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.output),
            tooltip: 'Print Delta JSON to log',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content:
                      Text('The JSON Delta has been printed to the console.')));
              debugPrint(jsonEncode(_controller.document.toDelta().toJson()));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            QuillSimpleToolbar(
              controller: _controller,
              config: QuillSimpleToolbarConfig(
                embedButtons: FlutterQuillEmbeds.toolbarButtons(),
                showClipboardPaste: true,
                customButtons: [
                  QuillToolbarCustomButtonOptions(
                    icon: const Icon(Icons.add_alarm_rounded),
                    onPressed: () {
                      _controller.document.insert(
                        _controller.selection.extentOffset,
                        TimeStampEmbed(
                          DateTime.now().toString(),
                        ),
                      );

                      _controller.updateSelection(
                        TextSelection.collapsed(
                          offset: _controller.selection.extentOffset + 1,
                        ),
                        ChangeSource.local,
                      );
                    },
                  ),
                ],
                buttonOptions: QuillSimpleToolbarButtonOptions(
                  base: QuillToolbarBaseButtonOptions(
                    afterButtonPressed: () {
                      final isDesktop = {
                        TargetPlatform.linux,
                        TargetPlatform.windows,
                        TargetPlatform.macOS
                      }.contains(defaultTargetPlatform);
                      if (isDesktop) {
                        _editorFocusNode.requestFocus();
                      }
                    },
                  ),
                  linkStyle: QuillToolbarLinkStyleButtonOptions(
                    validateLink: (link) {
                      // Treats all links as valid. When launching the URL,
                      // `https://` is prefixed if the link is incomplete (e.g., `google.com` → `https://google.com`)
                      // however this happens only within the editor.
                      return true;
                    },
                  ),
                ),
              ),
            ),
            Expanded(
              child: QuillEditor(
                key: _editorKey,
                focusNode: _editorFocusNode,
                scrollController: _editorScrollController,
                controller: _controller,
                config: QuillEditorConfig(
                  placeholder: 'Start writing your notes...',
                  padding: const EdgeInsets.all(16),
                  embedBuilders: [
                    ...FlutterQuillEmbeds.editorBuilders(
                      imageEmbedConfig: QuillEditorImageEmbedConfig(
                        imageProviderBuilder: (context, imageUrl) {
                          // https://pub.dev/packages/flutter_quill_extensions#-image-assets
                          if (imageUrl.startsWith('assets/')) {
                            return AssetImage(imageUrl);
                          }
                          return null;
                        },
                      ),
                      videoEmbedConfig: QuillEditorVideoEmbedConfig(
                        customVideoBuilder: (videoUrl, readOnly) {
                          // To load YouTube videos https://github.com/singerdmx/flutter-quill/releases/tag/v10.8.0
                          return null;
                        },
                      ),
                    ),
                    TimeStampEmbedBuilder(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _editorScrollController.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }
}

class TimeStampEmbed extends Embeddable {
  const TimeStampEmbed(
    String value,
  ) : super(timeStampType, value);

  static const String timeStampType = 'timeStamp';

  static TimeStampEmbed fromDocument(Document document) =>
      TimeStampEmbed(jsonEncode(document.toDelta().toJson()));

  Document get document => Document.fromJson(jsonDecode(data));
}

class TimeStampEmbedBuilder extends EmbedBuilder {
  @override
  String get key => 'timeStamp';

  @override
  String toPlainText(Embed node) {
    return node.value.data;
  }

  @override
  Widget build(
    BuildContext context,
    EmbedContext embedContext,
  ) {
    return Row(
      children: [
        const Icon(Icons.access_time_rounded),
        Text(embedContext.node.value.data as String),
      ],
    );
  }
}
