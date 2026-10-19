import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/FolkTheme.dart';

/// "Note [3] of 30": the number is a small typeable box (the same look as the reader's chapter jump).
/// Type a number and press Done to jump to that card; [onSubmitted] receives what was typed. The box
/// follows [number] when the cards are swiped, and shows the real number again if it is left without Done.
class NoteJump extends StatefulWidget {
  const NoteJump({
    super.key,
    required this.number,
    required this.total,
    required this.textColor,
    required this.onSubmitted,
    this.suffix = '',
  });

  /// The card on screen (1-based).
  final int number;
  final int total;
  final Color textColor;
  final ValueChanged<String> onSubmitted;

  /// Extra words after "of 30" (for example the percentage).
  final String suffix;

  @override
  State<NoteJump> createState() => _NoteJumpState();
}

class _NoteJumpState extends State<NoteJump> {
  late final TextEditingController _controller = TextEditingController(text: '${widget.number}');
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _showCurrent();
    });
  }

  @override
  void didUpdateWidget(NoteJump old) {
    super.didUpdateWidget(old);
    if (old.number != widget.number && !_focus.hasFocus) _showCurrent();
  }

  void _showCurrent() => _controller.text = '${widget.number}';

  void _submit(String value) {
    _focus.unfocus();
    widget.onSubmitted(value);
    // An invalid entry leaves the card where it is; either way the box shows the card on screen.
    _showCurrent();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final style = text.bodyStrong.copyWith(color: widget.textColor);
    final digits = math.max(2, '${widget.total}'.length);
    final scale = MediaQuery.textScalerOf(context).scale(1);
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Flexible(child: Text('Note', maxLines: 1, overflow: TextOverflow.ellipsis, style: style)),
        const SizedBox(width: 8),
        Semantics(
          label: 'Note number, type a number to jump',
          textField: true,
          child: SizedBox(
            width: (digits * 10.0 + 24) * scale,
            child: TextField(
              key: const ValueKey('note-jump-box'),
              controller: _controller,
              focusNode: _focus,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(5)],
              textAlign: TextAlign.center,
              maxLines: 1,
              style: style,
              cursorColor: widget.textColor,
              onTap: () => _controller.selection = TextSelection(baseOffset: 0, extentOffset: _controller.text.length),
              onSubmitted: _submit,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: widget.textColor.withValues(alpha: .08),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.textColor.withValues(alpha: .55)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.textColor.withValues(alpha: .55)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: widget.textColor, width: 1.6),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text('of ${widget.total}${widget.suffix}', maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
        ),
      ],
    );
  }
}
