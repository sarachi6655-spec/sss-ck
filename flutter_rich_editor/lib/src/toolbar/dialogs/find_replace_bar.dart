import 'package:flutter/material.dart';
import '../../core/controller/rich_editor_controller.dart';
import '../../core/document_model/editor_node.dart';
import '../../core/document_model/editor_selection.dart';
import '../../theme/editor_theme.dart';

class FindReplaceBar extends StatefulWidget {
  const FindReplaceBar({
    super.key,
    required this.controller,
    required this.onClose,
    this.theme = const EditorTheme(),
  });

  final RichEditorController controller;
  final VoidCallback onClose;
  final EditorTheme theme;

  @override
  State<FindReplaceBar> createState() => _FindReplaceBarState();
}

class _FindReplaceBarState extends State<FindReplaceBar> {
  final TextEditingController _findController = TextEditingController();
  final TextEditingController _replaceController = TextEditingController();
  bool _matchCase = false;
  int _currentMatchIndex = 0;
  List<_MatchLocation> _matches = <_MatchLocation>[];

  @override
  void initState() {
    super.initState();
    _findController.addListener(_performSearch);
  }

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    super.dispose();
  }

  void _performSearch() {
    final String query = _findController.text;
    if (query.isEmpty) {
      setState(() {
        _matches = <_MatchLocation>[];
        _currentMatchIndex = 0;
      });
      return;
    }

    final List<_MatchLocation> found = <_MatchLocation>[];
    for (int n = 0; n < widget.controller.document.nodes.length; n++) {
      final EditorNode node = widget.controller.document.nodes[n];
      final String text = node.text;
      final String searchIn = _matchCase ? text : text.toLowerCase();
      final String searchFor = _matchCase ? query : query.toLowerCase();

      int startIndex = 0;
      while ((startIndex = searchIn.indexOf(searchFor, startIndex)) != -1) {
        found.add(_MatchLocation(
          nodeIndex: n,
          startOffset: startIndex,
          endOffset: startIndex + query.length,
        ));
        startIndex += query.length;
      }
    }

    setState(() {
      _matches = found;
      _currentMatchIndex = found.isNotEmpty ? 1 : 0;
    });

    if (found.isNotEmpty) {
      _highlightCurrentMatch();
    }
  }

  void _highlightCurrentMatch() {
    if (_matches.isEmpty || _currentMatchIndex < 1 || _currentMatchIndex > _matches.length) return;
    final _MatchLocation match = _matches[_currentMatchIndex - 1];
    widget.controller.setSelection(EditorSelection(
      baseOffset: match.startOffset,
      extentOffset: match.endOffset,
      nodeIndex: match.nodeIndex,
    ));
  }

  void _nextMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = (_currentMatchIndex % _matches.length) + 1;
    });
    _highlightCurrentMatch();
  }

  void _prevMatch() {
    if (_matches.isEmpty) return;
    setState(() {
      _currentMatchIndex = _currentMatchIndex <= 1 ? _matches.length : _currentMatchIndex - 1;
    });
    _highlightCurrentMatch();
  }

  void _replaceCurrent() {
    if (_matches.isEmpty || _currentMatchIndex < 1 || _currentMatchIndex > _matches.length) return;
    final _MatchLocation match = _matches[_currentMatchIndex - 1];
    final String replacement = _replaceController.text;

    final List<EditorNode> updatedNodes = List<EditorNode>.from(widget.controller.document.nodes);
    final EditorNode node = updatedNodes[match.nodeIndex];
    final String newText = node.text.replaceRange(match.startOffset, match.endOffset, replacement);
    updatedNodes[match.nodeIndex] = node.copyWith(text: newText);

    widget.controller.import(widget.controller.document.copyWith(nodes: updatedNodes));
    _performSearch();
  }

  void _replaceAll() {
    final String query = _findController.text;
    final String replacement = _replaceController.text;
    if (query.isEmpty) return;

    final List<EditorNode> updatedNodes = List<EditorNode>.from(widget.controller.document.nodes);
    for (int i = 0; i < updatedNodes.length; i++) {
      final EditorNode node = updatedNodes[i];
      if (_matchCase) {
        updatedNodes[i] = node.copyWith(text: node.text.replaceAll(query, replacement));
      } else {
        final RegExp regex = RegExp(RegExp.escape(query), caseSensitive: false);
        updatedNodes[i] = node.copyWith(text: node.text.replaceAll(regex, replacement));
      }
    }

    widget.controller.import(widget.controller.document.copyWith(nodes: updatedNodes));
    _performSearch();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 4.0,
      color: Colors.white,
      borderRadius: BorderRadius.circular(8.0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8.0),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.search, size: 20, color: Colors.grey),
                const SizedBox(width: 8.0),
                Expanded(
                  child: TextField(
                    controller: _findController,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: 'Find in document...',
                      border: InputBorder.none,
                      isDense: true,
                      suffixText: _matches.isNotEmpty
                          ? '$_currentMatchIndex of ${_matches.length}'
                          : (_findController.text.isNotEmpty ? '0 found' : ''),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_up, size: 20),
                  tooltip: 'Previous match',
                  onPressed: _matches.isNotEmpty ? _prevMatch : null,
                ),
                IconButton(
                  icon: const Icon(Icons.keyboard_arrow_down, size: 20),
                  tooltip: 'Next match',
                  onPressed: _matches.isNotEmpty ? _nextMatch : null,
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: 'Close search',
                  onPressed: widget.onClose,
                ),
              ],
            ),
            const Divider(height: 12.0),
            Row(
              children: <Widget>[
                const Icon(Icons.find_replace, size: 20, color: Colors.grey),
                const SizedBox(width: 8.0),
                Expanded(
                  child: TextField(
                    controller: _replaceController,
                    decoration: const InputDecoration(
                      hintText: 'Replace with...',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _matches.isNotEmpty ? _replaceCurrent : null,
                  child: const Text('Replace'),
                ),
                TextButton(
                  onPressed: _matches.isNotEmpty ? _replaceAll : null,
                  child: const Text('Replace All'),
                ),
                InkWell(
                  onTap: () {
                    setState(() {
                      _matchCase = !_matchCase;
                    });
                    _performSearch();
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                    child: Text(
                      'Aa',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _matchCase ? const Color(0xFF2563EB) : Colors.grey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MatchLocation {
  const _MatchLocation({
    required this.nodeIndex,
    required this.startOffset,
    required this.endOffset,
  });

  final int nodeIndex;
  final int startOffset;
  final int endOffset;
}
