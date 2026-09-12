import 'package:flutter/material.dart';

/// State-preserving inline editor for subtitle text that maintains cursor selection
/// even when the parent widget updates.
class StudioSubtitleInlineEditor extends StatefulWidget {
  final String text;
  final TextStyle style;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;

  const StudioSubtitleInlineEditor({
    super.key,
    required this.text,
    required this.style,
    required this.decoration,
    required this.onChanged,
  });

  @override
  State<StudioSubtitleInlineEditor> createState() => _StudioSubtitleInlineEditorState();
}

class _StudioSubtitleInlineEditorState extends State<StudioSubtitleInlineEditor> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(covariant StudioSubtitleInlineEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && _controller.text != widget.text) {
      final oldSelection = _controller.selection;
      _controller.text = widget.text;
      if (oldSelection.start <= widget.text.length && oldSelection.end <= widget.text.length) {
        _controller.selection = oldSelection;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      style: widget.style,
      decoration: widget.decoration,
      maxLines: null,
      onChanged: widget.onChanged,
    );
  }
}
