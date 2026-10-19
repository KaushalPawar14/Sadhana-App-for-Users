import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GradientCard.dart';

/// The two square buttons under the Books screen's sections: "Notes" and "History", side by side. Each is a
/// theme gradient tile (the same on Light and Dark) with an icon over its label.
class BookExtrasRow extends StatelessWidget {
  const BookExtrasRow({super.key, required this.onNotes, required this.onHistory});

  final VoidCallback onNotes;
  final VoidCallback onHistory;

  Widget _square(BuildContext context, {required Key key, required String label, required IconData icon, required FolkGradientStyle style, required VoidCallback onTap}) {
    final text = context.folkText;
    return Expanded(
      child: AspectRatio(
        aspectRatio: 1,
        child: GradientCard(
          key: key,
          style: style,
          semanticLabel: label,
          onTap: onTap,
          padding: const EdgeInsets.all(FolkSpace.lg),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40),
              const SizedBox(height: FolkSpace.md),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodyStrong.copyWith(color: FolkColors.onGradient),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: FolkSpace.lg),
      child: Row(
        children: [
          _square(context, key: const ValueKey('books-notes-button'), label: 'Notes', icon: Icons.sticky_note_2_outlined, style: FolkGradientStyle.violet, onTap: onNotes),
          const SizedBox(width: FolkSpace.cardGap),
          _square(context, key: const ValueKey('books-history-button'), label: 'History', icon: Icons.history_rounded, style: FolkGradientStyle.saffron, onTap: onHistory),
        ],
      ),
    );
  }
}
