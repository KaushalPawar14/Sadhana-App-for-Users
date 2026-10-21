import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookHighlights.dart';
import 'PrimaryButton.dart';

/// The steps of "How notes work" (Books -> Notes -> the "i" button).
const List<String> kNotesHowSteps = [
  'While reading, long-press any text to select it (use Sentence or Paragraph to select quickly).',
  'Choose Good, Excellent or Rare, add a note if you like, and tap Highlight.',
  'Have a doubt about a passage? Choose Doubt, write your question, and ask the AI or your guide. The answer comes back to you under Doubts.',
  'Tap a highlight to read or edit its note; long-press it to resize or delete.',
  'Find all your highlights and doubts here: choose a category → a book → swipe through the numbered notes, or type a number to jump.',
  'Your highlights and notes are private — only you can see them.',
];

/// The step that shows the three category chips under its text.
const int kNotesHowChipStep = 1;

/// Opens the "How notes work" bottom sheet: scrollable, closed by tapping outside, dragging down or the Close button.
Future<void> showNotesHowItWorks(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
    builder: (sheetContext) => const NotesHowItWorksSheet(),
  );
}

class NotesHowItWorksSheet extends StatelessWidget {
  const NotesHowItWorksSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Container(
      key: const ValueKey('notes-how-sheet'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(FolkShape.cardRadius)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(color: colors.surfaceSecondary, borderRadius: BorderRadius.circular(4)),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('How notes work', style: text.topBarTitle.copyWith(fontSize: 18)),
                  const SizedBox(height: 16),
                  for (var i = 0; i < kNotesHowSteps.length; i++) ...[
                    _Step(number: i + 1, text: kNotesHowSteps[i], withChips: i == kNotesHowChipStep),
                    if (i < kNotesHowSteps.length - 1) const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: PrimaryButton(label: 'Close', onPressed: () => Navigator.of(context).pop()),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.text, required this.withChips});

  final int number;
  final String text;
  final bool withChips;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final styles = context.folkText;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceSecondary),
          child: Text('$number', style: styles.bodyStrong.copyWith(fontSize: 14)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(text, style: styles.body),
              ),
              if (withChips) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [for (final c in HighlightCategory.values) _CategoryChip(category: c)],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// A small chip in the category's tile colours (the same gradients as the Notes tiles), ink text.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category});

  final HighlightCategory category;

  static LinearGradient gradientOf(HighlightCategory c) => switch (c) {
        HighlightCategory.good => FolkGradients.saffron,
        HighlightCategory.excellent => FolkGradients.green,
        HighlightCategory.rare => FolkGradients.violet,
        HighlightCategory.doubt => FolkGradients.slate,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      key: ValueKey('notes-how-chip-${category.key}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(gradient: gradientOf(category), borderRadius: BorderRadius.circular(FolkShape.chipHeight / 2)),
      child: Text(category.label, style: context.folkText.chip.copyWith(color: FolkColors.onGradient)),
    );
  }
}
