import 'package:flutter/material.dart';
import 'package:flutter_rich_editor/flutter_rich_editor.dart';

void main() {
  runApp(const RichEditorDemoApp());
}

class RichEditorDemoApp extends StatelessWidget {
  const RichEditorDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Rich Editor Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
        useMaterial3: true,
      ),
      home: const EditorShowcasePage(),
    );
  }
}

class EditorShowcasePage extends StatefulWidget {
  const EditorShowcasePage({super.key});

  @override
  State<EditorShowcasePage> createState() => _EditorShowcasePageState();
}

class _EditorShowcasePageState extends State<EditorShowcasePage> {
  late final RichEditorController _controller;
  int _themeIndex = 0; // 0: Light, 1: Dark, 2: Cyber/Vibrant

  final List<EditorTheme> _themes = <EditorTheme>[
    EditorTheme.light(),
    EditorTheme.dark(),
    const EditorTheme(
      backgroundColor: Color(0xFF1E1E2E),
      textColor: Color(0xFFCDD6F4),
      cursorColor: Color(0xFFF5C2E7),
      selectionColor: Color(0x4089B4FA),
      toolbarBackgroundColor: Color(0xFF313244),
      toolbarBorderColor: Color(0xFF45475A),
      toolbarItemColor: Color(0xFFBAC2DE),
      toolbarItemActiveColor: Color(0xFF89B4FA),
      toolbarItemActiveBackgroundColor: Color(0xFF45475A),
      codeBlockBackgroundColor: Color(0xFF181825),
      tableBorderColor: Color(0xFF45475A),
      tableHeaderBackgroundColor: Color(0xFF313244),
      blockquoteBorderColor: Color(0xFF6C7086),
      blockquoteBackgroundColor: Color(0xFF181825),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = RichEditorController(
      initialDocument: DocumentValue(
        nodes: <EditorNode>[
          EditorNode.heading(
            id: 'h1',
            text: 'CKEditor 5 Alternative for Flutter',
            level: 1,
            attributes: const <String, dynamic>{'bold': true},
          ),
          EditorNode.paragraph(
            id: 'p1',
            text: 'Welcome to sss_rich_editor! A fully native, highly configurable rich text engine built from scratch.',
          ),
          EditorNode.listItem(
            id: 'l1',
            text: 'Dynamic theming with 50+ customizable color tokens',
            listType: 'bullet',
          ),
          EditorNode.listItem(
            id: 'l2',
            text: 'Native video upload and responsive playback controls',
            listType: 'bullet',
          ),
          EditorNode.listItem(
            id: 'l3',
            text: 'Interactive data tables with column resizing & cell merging',
            listType: 'bullet',
          ),
          EditorNode.codeBlock(
            id: 'c1',
            code: 'void main() {\n  print("Hello from LIMS Rich Editor!");\n}',
            language: 'dart',
          ),
          EditorNode.table(
            id: 't1',
            rows: 3,
            columns: 2,
            caption: 'Sample Clinical Parameters',
            rowNodes: <EditorNode>[
              EditorNode(
                id: 't1_r0',
                type: 'table_row',
                children: <EditorNode>[
                  EditorNode(id: 't1_c0_0', type: 'table_cell', text: '20'),
                  EditorNode(id: 't1_c0_1', type: 'table_cell', text: 'Glucose (mg/dL)'),
                ],
              ),
              EditorNode(
                id: 't1_r1',
                type: 'table_row',
                children: <EditorNode>[
                  EditorNode(id: 't1_c1_0', type: 'table_cell', text: '30'),
                  EditorNode(id: 't1_c1_1', type: 'table_cell', text: 'Cholesterol (mg/dL)'),
                ],
              ),
              EditorNode(
                id: 't1_r2',
                type: 'table_row',
                children: <EditorNode>[
                  EditorNode(id: 't1_c2_0', type: 'table_cell', text: '=SUM(A1:A2)'),
                  EditorNode(id: 't1_c2_1', type: 'table_cell', text: 'Total Score'),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showExportDialog(String title, String content) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: SelectableText(content),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final EditorTheme activeTheme = _themes[_themeIndex];

    return Scaffold(
      backgroundColor: activeTheme.backgroundColor,
      appBar: AppBar(
        title: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            return const Text(
              'Flutter Rich Editor Showcase',
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
        backgroundColor: activeTheme.toolbarBackgroundColor,
        foregroundColor: activeTheme.textColor,
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.palette_outlined),
            tooltip: 'Toggle Theme',
            onPressed: () {
              setState(() {
                _themeIndex = (_themeIndex + 1) % _themes.length;
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.html_outlined),
            tooltip: 'Export HTML',
            onPressed: () => _showExportDialog('Exported Semantic HTML', _controller.toHtml()),
          ),
          IconButton(
            icon: const Icon(Icons.code),
            tooltip: 'Export Markdown',
            onPressed: () => _showExportDialog('Exported Markdown', _controller.toMarkdown()),
          ),
          IconButton(
            icon: const Icon(Icons.fullscreen),
            tooltip: 'Fullscreen Mode',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FullscreenEditor(
                    controller: _controller,
                    theme: activeTheme,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double horizontalPadding = constraints.maxWidth < 600
                ? 0.0
                : (constraints.maxWidth < 1024 ? 8.0 : 16.0);
            final double verticalPadding = constraints.maxWidth < 600
                ? 0.0
                : (constraints.maxWidth < 1024 ? 8.0 : 16.0);

            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: horizontalPadding,
                vertical: verticalPadding,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(constraints.maxWidth < 600 ? 0.0 : 8.0),
                child: RichEditor(
                  controller: _controller,
                  theme: activeTheme,
                  config: const EditorConfig(
                    placeholder: 'Type your clinical observations or research notes here...',
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
