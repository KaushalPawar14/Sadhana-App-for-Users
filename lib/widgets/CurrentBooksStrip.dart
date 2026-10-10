import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkCard.dart';
import 'PressScale.dart';

class CurrentBookItem {
  const CurrentBookItem({
    required this.level,
    required this.levelLabel,
    required this.bookKey,
    required this.title,
  });

  final String level;
  final String levelLabel;
  final String bookKey;
  final String title;
}

// "CURRENT BOOKS": every book the student is reading right now, at the top of
// the Books list. One tap on a book opens it. With no current books it is not
// there at all. Each book is its own row: a title (up to three lines) and its
// level, as tall as it needs to be at any text size.
class CurrentBooksStrip extends StatelessWidget {
  const CurrentBooksStrip({
    super.key,
    required this.books,
    required this.onOpen,
  });

  final List<CurrentBookItem> books;
  final ValueChanged<CurrentBookItem> onOpen;

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    final text = context.folkText;
    final colors = context.folk;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Semantics(
            header: true,
            child: Text('CURRENT BOOKS', style: text.label),
          ),
        ),
        for (final book in books)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Semantics(
              button: true,
              label: 'Continue reading ${book.title}, ${book.levelLabel}',
              excludeSemantics: true,
              onTap: () => onOpen(book),
              child: PressScale(
                child: FolkCard(
                  padding: EdgeInsets.zero,
                  radius: FolkShape.tileRadius,
                  child: Material(
                    type: MaterialType.transparency,
                    borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () => onOpen(book),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                            minHeight: FolkShape.touchTarget),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: FolkGradients.violet,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: const Icon(Icons.menu_book,
                                    size: 20, color: FolkColors.onGradient),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      book.title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: text.bodyStrong
                                          .copyWith(height: 1.25),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(book.levelLabel, style: text.caption),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right_rounded,
                                  color: colors.mutedText),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
