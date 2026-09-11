import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_rich_editor/src/core/document_model/document_model.dart';
import 'package:flutter_rich_editor/src/core/plugin_system/plugin_system.dart';
import 'package:flutter_rich_editor/src/features/formatting/formatting_plugin.dart';

EditorCommandContext _ctx(
  DocumentValue doc,
  EditorSelection sel, {
  bool readOnly = false,
}) =>
    EditorCommandContext(document: doc, selection: sel, readOnly: readOnly);

void main() {
  group('ToggleMarkCommand', () {
    test('id reflects mark name', () {
      const ToggleMarkCommand cmd = ToggleMarkCommand(mark: 'bold');
      expect(cmd.id, 'formatting/toggle_bold');
    });

    test('fails when selection has no nodeId', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'bold');
      final EditorCommandResult r = cmd.execute(_ctx(
        DocumentValue.empty,
        const EditorSelection.none(),
      ));
      expect(r.success, isFalse);
      expect(r.errorCode, 'selection.empty');
    });

    test('fails when document is empty', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'bold');
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r =
          cmd.execute(_ctx(DocumentValue.empty, sel));
      expect(r.success, isFalse);
      expect(r.errorCode, 'selection.empty');
    });

    test('fails when selected node is missing', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'bold');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'missing',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isFalse);
      expect(r.errorCode, 'node.missing');
    });

    test('toggles mark on range selection', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'bold');
      final ParagraphNode p = ParagraphNode.fromText(
        id: 'p1',
        text: 'hello world',
      );
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.range(
        nodeId: 'p1',
        startOffset: 0,
        endOffset: 5,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(r.document, isNotNull);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      // The first 5 characters (hello) should now have bold.
      expect(updated.spans.first.text, 'hello');
      expect(updated.spans.first.marks.contains('bold'), isTrue);
      expect(updated.spans.last.text, ' world');
      expect(updated.spans.last.marks.contains('bold'), isFalse);
    });

    test('applies mark across whole paragraph when collapsed', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'italic');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'abc');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 1,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.plainText, 'abc');
      expect(updated.spans.first.marks.contains('italic'), isTrue);
    });

    test('increments document version', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'bold');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[p],
        version: 3,
      );
      const EditorSelection sel = EditorSelection.range(
        nodeId: 'p1',
        startOffset: 0,
        endOffset: 2,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.document!.version, 4);
    });

    test('undo restores previous document', () {
      const EditorCommand cmd = ToggleMarkCommand(mark: 'bold');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.range(
        nodeId: 'p1',
        startOffset: 0,
        endOffset: 2,
      );
      final EditorCommandResult r = cmd.undo(_ctx(doc, sel), doc);
      expect(r.success, isTrue);
      expect(r.document, doc);
    });
  });

  group('RemoveFormattingCommand', () {
    test('id is formatting/remove_format', () {
      const RemoveFormattingCommand cmd = RemoveFormattingCommand();
      expect(cmd.id, 'formatting/remove_format');
    });

    test('fails when selection is empty', () {
      const RemoveFormattingCommand cmd = RemoveFormattingCommand();
      final EditorCommandResult r = cmd.execute(_ctx(
        DocumentValue.empty,
        const EditorSelection.none(),
      ));
      expect(r.success, isFalse);
      expect(r.errorCode, 'selection.empty');
    });

    test('returns success without change for non-paragraph nodes', () {
      // Use UnsupportedNode which is not a ParagraphNode.
      const RemoveFormattingCommand cmd = RemoveFormattingCommand();
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          UnsupportedNode(
            id: 'u1',
            originalType: 'foo',
            json: <String, dynamic>{},
          ),
        ],
      );
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'u1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(r.document, doc);
    });

    test('strips marks across a range', () {
      const RemoveFormattingCommand cmd = RemoveFormattingCommand();
      final ParagraphNode p = ParagraphNode(
        id: 'p1',
        spans: const <TextSpanNode>[
          TextSpanNode(text: 'hi', marks: <String>{'bold', 'italic'}),
        ],
      );
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.range(
        nodeId: 'p1',
        startOffset: 0,
        endOffset: 2,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.spans.first.marks, isEmpty);
    });

    test('undo restores previous document', () {
      const RemoveFormattingCommand cmd = RemoveFormattingCommand();
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      final EditorCommandResult r = cmd.undo(_ctx(doc, const EditorSelection.none()), doc);
      expect(r.document, doc);
    });
  });

  group('SetAlignmentCommand', () {
    test('id is formatting/set_alignment', () {
      const SetAlignmentCommand cmd = SetAlignmentCommand(alignment: 'center');
      expect(cmd.id, 'formatting/set_alignment');
    });

    test('sets alignment attribute on paragraph', () {
      const SetAlignmentCommand cmd = SetAlignmentCommand(alignment: 'right');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.attributes['align'], 'right');
    });

    test('fails on non-paragraph node', () {
      const SetAlignmentCommand cmd = SetAlignmentCommand(alignment: 'left');
      final DocumentValue doc = DocumentValue(
        nodes: <EditorNode>[
          UnsupportedNode(
            id: 'u',
            originalType: 'x',
            json: <String, dynamic>{},
          ),
        ],
      );
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'u',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isFalse);
      expect(r.errorCode, 'node.invalid');
    });
  });

  group('SetIndentCommand', () {
    test('id is formatting/set_indent', () {
      const SetIndentCommand cmd = SetIndentCommand(delta: 1);
      expect(cmd.id, 'formatting/set_indent');
    });

    test('increments indent by delta', () {
      const SetIndentCommand cmd = SetIndentCommand(delta: 2);
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.attributes['indent'], 2);
    });

    test('clamps indent to maximum of 8', () {
      const SetIndentCommand cmd = SetIndentCommand(delta: 100);
      final ParagraphNode p = ParagraphNode.fromText(
        id: 'p1',
        text: 'hi',
      ).setAttribute('indent', 7);
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.document, isNotNull);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.attributes['indent'], 8);
    });

    test('clamps indent to minimum of 0', () {
      const SetIndentCommand cmd = SetIndentCommand(delta: -5);
      final ParagraphNode p = ParagraphNode.fromText(
        id: 'p1',
        text: 'hi',
      ).setAttribute('indent', 2);
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.attributes['indent'], 0);
    });
  });

  group('SetColorCommand', () {
    test('id is formatting/set_color', () {
      const SetColorCommand cmd = SetColorCommand(color: '#FF0000');
      expect(cmd.id, 'formatting/set_color');
    });

    test('accepts hex color', () {
      const SetColorCommand cmd = SetColorCommand(color: '#FF0000');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(
        (r.document!.nodes.first as ParagraphNode).attributes['color'],
        '#FF0000',
      );
    });

    test('accepts rgb color', () {
      const SetColorCommand cmd = SetColorCommand(color: 'rgb(1, 2, 3)');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
    });

    test('rejects invalid color', () {
      const SetColorCommand cmd = SetColorCommand(color: 'not-a-color');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isFalse);
      expect(r.errorCode, 'format.invalidColor');
    });

    test('null color clears attribute', () {
      const SetColorCommand cmd = SetColorCommand(color: null);
      final ParagraphNode p = ParagraphNode.fromText(
        id: 'p1',
        text: 'hi',
      ).setAttribute('color', '#FF0000');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(
        (r.document!.nodes.first as ParagraphNode).attributes.containsKey(
          'color',
        ),
        isFalse,
      );
    });

    test('background flag uses background attribute key', () {
      const SetColorCommand cmd = SetColorCommand(
        color: '#ABCDEF',
        background: true,
      );
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(
        (r.document!.nodes.first as ParagraphNode).attributes['background'],
        '#ABCDEF',
      );
    });
  });

  group('SetFontCommand', () {
    test('id is formatting/set_font', () {
      const SetFontCommand cmd = SetFontCommand(family: 'Arial');
      expect(cmd.id, 'formatting/set_font');
    });

    test('sets both family and size', () {
      const SetFontCommand cmd = SetFontCommand(family: 'Arial', size: 18);
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      final ParagraphNode updated =
          r.document!.nodes.first as ParagraphNode;
      expect(updated.attributes['fontFamily'], 'Arial');
      expect(updated.attributes['fontSize'], 18);
    });

    test('family and size are independently optional', () {
      const SetFontCommand cmd = SetFontCommand(family: 'Arial');
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(
        (r.document!.nodes.first as ParagraphNode).attributes['fontFamily'],
        'Arial',
      );
      expect(
        (r.document!.nodes.first as ParagraphNode).attributes.containsKey(
          'fontSize',
        ),
        isFalse,
      );
    });
  });

  group('SetLineHeightCommand', () {
    test('id is formatting/set_line_height', () {
      const SetLineHeightCommand cmd = SetLineHeightCommand(lineHeight: 2.0);
      expect(cmd.id, 'formatting/set_line_height');
    });

    test('sets lineHeight attribute', () {
      const SetLineHeightCommand cmd = SetLineHeightCommand(lineHeight: 2.0);
      final ParagraphNode p = ParagraphNode.fromText(id: 'p1', text: 'hi');
      final DocumentValue doc = DocumentValue(nodes: <EditorNode>[p]);
      const EditorSelection sel = EditorSelection.collapsed(
        nodeId: 'p1',
        offset: 0,
      );
      final EditorCommandResult r = cmd.execute(_ctx(doc, sel));
      expect(r.success, isTrue);
      expect(
        (r.document!.nodes.first as ParagraphNode).attributes['lineHeight'],
        2.0,
      );
    });
  });

  group('FormattingPlugin', () {
    test('id and name', () {
      final FormattingPlugin p = FormattingPlugin();
      expect(p.id, 'formatting/core');
      expect(p.name, 'Text Formatting');
      expect(p.dependencies, isEmpty);
    });

    test('register registers node type and toolbar items', () {
      final FormattingPlugin p = FormattingPlugin();
      final PluginRegistry registry = PluginRegistry();
      p.register(registry);
      expect(registry.nodeTypes, contains('paragraph'));
      // All formatting commands registered.
      for (final String mark in const <String>[
        'bold',
        'italic',
        'underline',
        'strikethrough',
        'subscript',
        'superscript',
        'code',
      ]) {
        expect(registry.commandIds, contains('formatting/toggle_$mark'));
      }
      expect(registry.commandIds, contains('formatting/remove_format'));
      expect(registry.commandIds, contains('formatting/set_alignment'));
      expect(registry.commandIds, contains('formatting/set_indent'));
      expect(registry.commandIds, contains('formatting/set_color'));
      expect(registry.commandIds, contains('formatting/set_font'));
      expect(registry.commandIds, contains('formatting/set_line_height'));
      // Toolbar items registered (10 items in this plugin).
      expect(registry.toolbarItems, isNotEmpty);
    });

    test('command factories build commands', () {
      final FormattingPlugin p = FormattingPlugin();
      final PluginRegistry registry = PluginRegistry();
      p.register(registry);
      // Build a ToggleBoldCommand via the factory.
      final EditorCommand cmd = registry.createCommand('formatting/toggle_bold');
      expect(cmd, isA<ToggleMarkCommand>());
      expect(cmd.id, 'formatting/toggle_bold');

      // Build SetAlignmentCommand with arguments.
      final EditorCommand alignCmd = registry.createCommand(
        'formatting/set_alignment',
        arguments: <String, dynamic>{'alignment': 'center'},
      );
      expect(alignCmd, isA<SetAlignmentCommand>());

      // Build SetColorCommand with arguments.
      final EditorCommand colorCmd = registry.createCommand(
        'formatting/set_color',
        arguments: <String, dynamic>{'color': '#FF0000'},
      );
      expect(colorCmd, isA<SetColorCommand>());

      // Build SetIndentCommand with arguments.
      final EditorCommand indentCmd = registry.createCommand(
        'formatting/set_indent',
        arguments: <String, dynamic>{'delta': 1},
      );
      expect(indentCmd, isA<SetIndentCommand>());

      // Build SetFontCommand with arguments.
      final EditorCommand fontCmd = registry.createCommand(
        'formatting/set_font',
        arguments: <String, dynamic>{'family': 'Arial', 'size': 14.0},
      );
      expect(fontCmd, isA<SetFontCommand>());

      // Build SetLineHeightCommand with arguments.
      final EditorCommand lhCmd = registry.createCommand(
        'formatting/set_line_height',
        arguments: <String, dynamic>{'lineHeight': 1.8},
      );
      expect(lhCmd, isA<SetLineHeightCommand>());

      // Build RemoveFormattingCommand with empty arguments.
      final EditorCommand removeCmd =
          registry.createCommand('formatting/remove_format');
      expect(removeCmd, isA<RemoveFormattingCommand>());
    });

    test('command factories use default values when arguments missing', () {
      final FormattingPlugin p = FormattingPlugin();
      final PluginRegistry registry = PluginRegistry();
      p.register(registry);
      final EditorCommand alignCmd = registry.createCommand(
        'formatting/set_alignment',
      );
      expect((alignCmd as SetAlignmentCommand).alignment, 'left');
      final EditorCommand indentCmd = registry.createCommand(
        'formatting/set_indent',
      );
      expect((indentCmd as SetIndentCommand).delta, 1);
      final EditorCommand lhCmd = registry.createCommand(
        'formatting/set_line_height',
      );
      expect((lhCmd as SetLineHeightCommand).lineHeight, 1.5);
    });
  });
}