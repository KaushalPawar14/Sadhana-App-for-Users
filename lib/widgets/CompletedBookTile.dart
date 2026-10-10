import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';

// One row of the "Completed books" section: the title and nothing else (no
// status, dates, Read or Update). Tapping it opens the book in the reader. As
// tall as the title needs at any text size, and never shorter than a touch
// target.
class CompletedBookTile extends StatelessWidget {
  const CompletedBookTile({
    super.key,
    required this.title,
    required this.onOpen,
  });

  final String title;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Semantics(
      button: true,
      label: 'Open $title',
      excludeSemantics: true,
      onTap: onOpen,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.menu_book,
                    size: 18, color: FolkCalendarTokens.legendSubmitted),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodyStrong.copyWith(height: 1.3),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: colors.mutedText),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
