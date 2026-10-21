import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/FormPoints.dart';
import 'FolkCard.dart';
import 'PointsChip.dart';
import 'PointsHelpSheet.dart';
import 'PressScale.dart';

// Look of the two Sadhana report forms (FOLK and hostel/localite). Only the
// drawing lives here: every field, its order, its validation and the submit
// write stay in the screens.

// The message under each field the last Submit rejected. One notifier per field,
// so showing or clearing a message repaints only that field, not the whole form.
class SadhanaFieldErrors {
  final Map<String, ValueNotifier<String?>> _notifiers = {};

  ValueNotifier<String?> of(String key) =>
      _notifiers.putIfAbsent(key, () => ValueNotifier<String?>(null));

  // Show exactly [errors] (a field not in it is cleared).
  void set(Map<String, String> errors) {
    for (final key in {..._notifiers.keys, ...errors.keys}) {
      of(key).value = errors[key];
    }
  }

  void clear() => set(const {});

  // Clears one field's message (nothing happens if it has none).
  void remove(String? key) {
    if (key == null) return;
    final n = _notifiers[key];
    if (n != null && n.value != null) n.value = null;
  }

  void dispose() {
    for (final n in _notifiers.values) {
      n.dispose();
    }
  }
}

// A field's decoration with its own error message, rebuilt on its own.
Widget sadhanaErrorBuilder(
  SadhanaFieldErrors errors,
  String? key,
  Widget Function(String? errorText) build,
) =>
    key == null
        ? build(null)
        : ValueListenableBuilder<String?>(
            valueListenable: errors.of(key),
            builder: (_, error, __) => build(error),
          );

// One question: the title, then the control (a field, a drop-down, options).
//
// Each card is its own repaint boundary: the shadow is painted once and kept, so
// a blinking cursor, a keystroke or the keyboard opening repaints one card, not
// every card and shadow in the form.
class FormQuestionCard extends StatelessWidget {
  const FormQuestionCard({
    super.key,
    required this.question,
    required this.child,
    this.trailing,
    this.onInfo,
  });

  final String question;
  final Widget child;

  /// The points chip of a scoring question ("+50 pts", "×1.5"), shown beside the title.
  final Widget? trailing;

  /// The "i" of a scoring question: opens its help sheet.
  final VoidCallback? onInfo;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return RepaintBoundary(
      child: FolkCard(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
        radius: FolkShape.tileRadius,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (onInfo == null && trailing == null)
              Text(question, style: text.bodyStrong)
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: Text(question, style: text.bodyStrong)),
                  if (trailing != null) Padding(padding: const EdgeInsets.only(left: 8), child: trailing),
                  if (onInfo != null) Transform.translate(offset: const Offset(8, 0), child: PointsInfoButton(label: 'How $question is scored', onPressed: onInfo!)),
                ],
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

// The filled, borderless input every field in the forms uses.
InputDecoration sadhanaFieldDecoration(
  BuildContext context, {
  String? hint,
  Widget? suffixIcon,
  String? errorText,
}) {
  final colors = context.folk;
  final text = context.folkText;
  return InputDecoration(
    filled: true,
    fillColor: colors.surfaceSecondary,
    hintText: hint,
    hintStyle: text.body.copyWith(color: colors.mutedText),
    suffixIcon: suffixIcon,
    errorText: errorText,
    errorStyle: text.caption.copyWith(color: colors.calendarMissedText),
    errorMaxLines: 3,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
      borderSide: BorderSide.none,
    ),
  );
}

// One choice among a few (the extra-lecture question). At least 48 dp tall;
// the label wraps at large text sizes.
class FormOptionRow extends StatelessWidget {
  const FormOptionRow({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final radius = BorderRadius.circular(FolkShape.tileRadius);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Material(
            color: selected ? colors.surface : colors.surfaceSecondary,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: selected
                  ? const BorderSide(
                      color: FolkCalendarTokens.selectedRing, width: 2.5)
                  : BorderSide.none,
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: Container(
                constraints:
                    const BoxConstraints(minHeight: FolkShape.touchTarget),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      size: 20,
                      color: selected ? colors.text : colors.mutedText,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(label, style: text.body)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Page padding the two forms share.
const EdgeInsets kSadhanaFormPadding = EdgeInsets.fromLTRB(
    FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, 32);

/// The live chip of a scoring question: repaints on its own when an answer changes, nothing while unanswered.
Widget pointsTrailing(LiveFormPoints points, PointsTopic topic) => ValueListenableBuilder<int>(
      valueListenable: points.tick,
      builder: (_, __, ___) {
        final chip = points.chipFor(topic);
        return chip == null ? const SizedBox.shrink() : PointsChip(key: ValueKey('chip-${topic.name}'), text: chip, multiplier: LiveFormPoints.isMultiplier(topic));
      },
    );
