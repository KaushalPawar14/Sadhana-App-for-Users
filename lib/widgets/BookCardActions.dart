import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkDialog.dart';

// The "Read" and "Update" buttons at the foot of a book card. Two equal
// halves; at large text sizes the labels stay on one line and shrink their
// padding rather than overflow.
class BookCardActions extends StatelessWidget {
  const BookCardActions({
    super.key,
    required this.onRead,
    required this.onUpdate,
  });

  final VoidCallback onRead;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    const size = Size(FolkShape.touchTarget, FolkShape.touchTarget);
    const padding = EdgeInsets.symmetric(horizontal: 12);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onRead,
            icon: const Icon(Icons.chrome_reader_mode, size: 17),
            label: const Text("Read", maxLines: 1, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(
              minimumSize: size,
              padding: padding,
              foregroundColor: colors.text,
              side: BorderSide(color: colors.mutedText),
              shape: const StadiumBorder(),
              textStyle: text.chip,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton.icon(
            onPressed: onUpdate,
            icon: const Icon(Icons.edit_note, size: 18),
            label: const Text("Update", maxLines: 1, overflow: TextOverflow.ellipsis),
            style: FolkDialog.primaryButton(colors, text).copyWith(
              padding: const WidgetStatePropertyAll(padding),
            ),
          ),
        ),
      ],
    );
  }
}
