import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkTypography.dart';
import '../utils/AssistantStarters.dart';
import 'GradientCard.dart';

// The four coloured question cards of an empty chat, one per category:
//
//   Spiritual question  PURPLE   (top-left)       How the app works  ORANGE  (top-right)
//   Daily practice      GREEN    (bottom-left)    How am I doing     PINK    (bottom-right)
//
// A 2x2 grid with purple and pink on the diagonal. When the text cannot fit a column at the
// student's text size, the cards stack full width in the same order (purple first, pink last).
// Text is the ink colour on every gradient, every card is at least 112 dp tall (so a 48 dp
// target with room), and nothing is clipped: a card grows with its text.
class AssistantStarterCards extends StatelessWidget {
  const AssistantStarterCards({
    super.key,
    required this.onPick,
    this.enabled = true,
    this.today,
  });

  // Called with the question text when a card is tapped (the chat's normal send).
  final ValueChanged<String> onPick;
  final bool enabled;

  // Tests choose the day; the app uses today.
  final DateTime? today;

  static const double _padding = 14;
  static const double _minHeight = 112;

  // The grid is used only while every question fits a column without breaking a word and
  // stays short enough; otherwise the cards stack.
  static bool fitsGrid(BuildContext context, List<String> questions, double columnWidth) {
    final text = context.folkText;
    final scaler = MediaQuery.textScalerOf(context);
    final inner = columnWidth - 2 * _padding;
    if (inner <= 0) return false;
    for (final q in questions) {
      final p = TextPainter(
        text: TextSpan(text: q, style: _questionStyle(text)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
      )..layout(maxWidth: inner);
      if (p.didExceedMaxLines || p.height > 170) return false;
      // no single word wider than the card
      for (final w in q.split(' ')) {
        final wp = TextPainter(
          text: TextSpan(text: w, style: _questionStyle(text)),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        if (wp.width > inner) return false;
      }
    }
    return true;
  }

  static TextStyle _questionStyle(FolkTypography text) =>
      text.bodyStrong.copyWith(color: FolkColors.onGradient, fontSize: 14, height: 1.3);

  @override
  Widget build(BuildContext context) {
    final questions = startersForDay(today ?? DateTime.now());
    final width = MediaQuery.sizeOf(context).width - 2 * FolkSpace.pagePadding;
    final column = (width - FolkSpace.sm) / 2;
    final grid = fitsGrid(context, questions, column);

    Widget card(int i) => _StarterCard(
          category: kStarterCategories[i],
          question: questions[i],
          enabled: enabled,
          onTap: () => onPick(questions[i]),
        );

    if (!grid) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < kStarterCategories.length; i++) ...[
            if (i > 0) const SizedBox(height: FolkSpace.sm),
            card(i),
          ],
        ],
      );
    }
    Widget row(int a, int b) => IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: card(a)),
              const SizedBox(width: FolkSpace.sm),
              Expanded(child: card(b)),
            ],
          ),
        );
    return Column(
      children: [
        row(0, 1), // purple | orange
        const SizedBox(height: FolkSpace.sm),
        row(2, 3), // green | pink
      ],
    );
  }
}

class _StarterCard extends StatelessWidget {
  const _StarterCard({
    required this.category,
    required this.question,
    required this.enabled,
    required this.onTap,
  });

  final StarterCategory category;
  final String question;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Opacity(
      opacity: enabled ? 1 : .6,
      child: GradientCard(
        style: category.style,
        padding: const EdgeInsets.all(AssistantStarterCards._padding),
        onTap: enabled ? onTap : null,
        semanticLabel: '${category.label}: $question',
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AssistantStarterCards._minHeight - 2 * AssistantStarterCards._padding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(category.label.toUpperCase(), style: text.label.copyWith(color: FolkColors.onGradientSecondary, fontSize: 11)),
              const SizedBox(height: 6),
              Text(question, style: AssistantStarterCards._questionStyle(text)),
            ],
          ),
        ),
      ),
    );
  }
}
