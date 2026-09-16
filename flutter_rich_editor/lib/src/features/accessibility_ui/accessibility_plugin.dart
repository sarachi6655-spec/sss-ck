import 'package:flutter/material.dart';
import '../../core/plugin_system/plugin.dart';

/// Localized labels for all editor UI components.
class EditorLocalizations {
  const EditorLocalizations({
    this.bold = 'Bold',
    this.italic = 'Italic',
    this.underline = 'Underline',
    this.strikethrough = 'Strikethrough',
    this.code = 'Code',
    this.heading1 = 'Heading 1',
    this.heading2 = 'Heading 2',
    this.heading3 = 'Heading 3',
    this.bulletList = 'Bullet List',
    this.numberedList = 'Numbered List',
    this.todoList = 'Todo List',
    this.blockquote = 'Blockquote',
    this.table = 'Table',
    this.image = 'Image',
    this.video = 'Video',
    this.link = 'Link',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.placeholder = 'Type something...',
    this.comments = 'Comments',
    this.save = 'Save',
    this.cancel = 'Cancel',
  });

  final String bold;
  final String italic;
  final String underline;
  final String strikethrough;
  final String code;
  final String heading1;
  final String heading2;
  final String heading3;
  final String bulletList;
  final String numberedList;
  final String todoList;
  final String blockquote;
  final String table;
  final String image;
  final String video;
  final String link;
  final String undo;
  final String redo;
  final String placeholder;
  final String comments;
  final String save;
  final String cancel;

  /// Default English localizations.
  static const EditorLocalizations en = EditorLocalizations();

  /// Spanish sample localizations.
  static const EditorLocalizations es = EditorLocalizations(
    bold: 'Negrita',
    italic: 'Cursiva',
    underline: 'Subrayado',
    strikethrough: 'Tachado',
    code: 'Código',
    heading1: 'Encabezado 1',
    heading2: 'Encabezado 2',
    heading3: 'Encabezado 3',
    bulletList: 'Lista con viñetas',
    numberedList: 'Lista numerada',
    todoList: 'Lista de tareas',
    blockquote: 'Cita',
    table: 'Tabla',
    image: 'Imagen',
    video: 'Video',
    link: 'Enlace',
    undo: 'Deshacer',
    redo: 'Rehacer',
    placeholder: 'Escribe algo...',
    comments: 'Comentarios',
    save: 'Guardar',
    cancel: 'Cancelar',
  );

  /// Replaces all visible editor labels with a custom mapping.
  EditorLocalizations copyWith({
    String? bold,
    String? italic,
    String? underline,
    String? strikethrough,
    String? code,
    String? heading1,
    String? heading2,
    String? heading3,
    String? bulletList,
    String? numberedList,
    String? todoList,
    String? blockquote,
    String? table,
    String? image,
    String? video,
    String? link,
    String? undo,
    String? redo,
    String? placeholder,
    String? comments,
    String? save,
    String? cancel,
  }) {
    return EditorLocalizations(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      code: code ?? this.code,
      heading1: heading1 ?? this.heading1,
      heading2: heading2 ?? this.heading2,
      heading3: heading3 ?? this.heading3,
      bulletList: bulletList ?? this.bulletList,
      numberedList: numberedList ?? this.numberedList,
      todoList: todoList ?? this.todoList,
      blockquote: blockquote ?? this.blockquote,
      table: table ?? this.table,
      image: image ?? this.image,
      video: video ?? this.video,
      link: link ?? this.link,
      undo: undo ?? this.undo,
      redo: redo ?? this.redo,
      placeholder: placeholder ?? this.placeholder,
      comments: comments ?? this.comments,
      save: save ?? this.save,
      cancel: cancel ?? this.cancel,
    );
  }
}

/// Accessibility and localization configuration for the editor.
class AccessibilityConfig {
  const AccessibilityConfig({
    this.textDirection = TextDirection.ltr,
    this.localizations = EditorLocalizations.en,
    this.enableSemantics = true,
  });

  final TextDirection textDirection;
  final EditorLocalizations localizations;
  final bool enableSemantics;
}

/// Plugin providing accessibility, RTL bidirectional layout, and localizations.
class AccessibilityPlugin extends EditorPlugin {
  const AccessibilityPlugin({
    this.config = const AccessibilityConfig(),
  });

  final AccessibilityConfig config;

  @override
  String get id => 'accessibility.ui';

  @override
  String get name => 'Accessibility & UI';
}
