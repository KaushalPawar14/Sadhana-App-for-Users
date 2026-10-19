import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookHighlights.dart';
import 'PressScale.dart';

// The pieces of highlights & notes that are drawn: the coloured portion inside a paragraph, the two drag handles,
// the category/note panel, the dialog of an existing highlight, and the floating action bar of focus mode. The
// reader (BookReaderPage) owns the state and decides when each appears.

// ---------------------------------------------------------------------------------------------------------
// the highlight inside a paragraph
// ---------------------------------------------------------------------------------------------------------

/// One portion of one paragraph to draw: characters [start, end), in a category's colour (or, for a selection that
/// has no category yet, [category] is null and a neutral tint is used).
@immutable
class PaintedRange {
  const PaintedRange(this.start, this.end, this.category);

  final int start;
  final int end;
  final HighlightCategory? category;

  @override
  bool operator ==(Object other) => other is PaintedRange && other.start == start && other.end == end && other.category == category;

  @override
  int get hashCode => Object.hash(start, end, category);
}

/// Paints the highlights BEHIND a paragraph's text: a soft translucent tint inside a thin rounded border in the
/// category colour (RARE also glows softly). The shape follows the text exactly - part of a line, several lines
/// - using the paragraph's own measured boxes; it never changes the paragraph's size or the line spacing.
class ParagraphHighlightPainter extends CustomPainter {
  ParagraphHighlightPainter({required this.textKey, required this.ranges, required this.neutral});

  /// The key of the paragraph's `RichText`.
  final GlobalKey textKey;
  final List<PaintedRange> ranges;

  /// The tint of a selection that has no category yet.
  final Color neutral;

  @override
  void paint(Canvas canvas, Size size) {
    if (ranges.isEmpty) return;
    final object = textKey.currentContext?.findRenderObject();
    if (object is! RenderParagraph || !object.hasSize) return;
    for (final r in ranges) {
      if (r.end <= r.start) continue;
      final boxes = object.getBoxesForSelection(
        TextSelection(baseOffset: r.start, extentOffset: r.end),
        boxHeightStyle: ui.BoxHeightStyle.max,
      );
      if (boxes.isEmpty) continue;
      var path = Path();
      for (final b in boxes) {
        final rect = b.toRect().inflate(1.5);
        path = Path.combine(PathOperation.union, path, Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(5))));
      }
      final category = r.category;
      if (category == null) {
        canvas.drawPath(path, Paint()..color = neutral);
        continue;
      }
      final color = Color(category.argb);
      if (category.glows) {
        canvas.drawPath(
          path,
          Paint()
            ..color = color.withValues(alpha: category.glowAlpha)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        );
      }
      canvas.drawPath(path, Paint()..color = Color(category.tintArgb));
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..strokeJoin = StrokeJoin.round
          ..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(ParagraphHighlightPainter old) =>
      old.textKey != textKey || old.neutral != neutral || !listEquals(old.ranges, ranges);
}

/// A tap/long-press target that exists ONLY over the highlighted characters of a paragraph: outside them the
/// touch falls through to the text below (so a long-press there starts a NEW selection, and scrolling is
/// untouched).
class HighlightHitGate extends LeafRenderObjectWidget {
  const HighlightHitGate({super.key, required this.accepts});

  /// Is this point (in the paragraph's own coordinates) on a highlighted character?
  final bool Function(Offset local) accepts;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHighlightHitGate(accepts);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderHighlightHitGate).accepts = accepts;
  }
}

class _RenderHighlightHitGate extends RenderBox {
  _RenderHighlightHitGate(this.accepts);

  bool Function(Offset local) accepts;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  bool hitTestSelf(Offset position) => accepts(position);
}

// ---------------------------------------------------------------------------------------------------------
// drag handles
// ---------------------------------------------------------------------------------------------------------

/// A drag handle at one end of a selection: a round knob on a short stem. The touch area is 44 x 44 dp.
class ReaderHandle extends StatelessWidget {
  const ReaderHandle({
    super.key,
    required this.color,
    required this.isStart,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final Color color;
  final bool isStart;
  final VoidCallback onDragStart;
  final ValueChanged<Offset> onDragUpdate; // the global pointer position
  final VoidCallback onDragEnd;

  static const double size = 44;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => onDragStart(),
      onPanUpdate: (d) => onDragUpdate(d.globalPosition),
      onPanEnd: (_) => onDragEnd(),
      onPanCancel: onDragEnd,
      child: SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _HandlePainter(color: color, isStart: isStart)),
      ),
    );
  }
}

class _HandlePainter extends CustomPainter {
  _HandlePainter({required this.color, required this.isStart});

  final Color color;
  final bool isStart;

  @override
  void paint(Canvas canvas, Size size) {
    // The stem hangs from the text's edge (top of the box) and the knob sits under it; the start handle's knob is
    // offset to the left, the end handle's to the right, like the platform's own handles.
    final x = size.width / 2;
    final knob = Offset(x + (isStart ? -3 : 3), 22);
    final paint = Paint()..color = color;
    canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, 14), paint);
    canvas.drawCircle(knob, 8, paint);
    canvas.drawCircle(knob, 8, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.white.withValues(alpha: .9));
  }

  @override
  bool shouldRepaint(_HandlePainter old) => old.color != color || old.isStart != isStart;
}

// ---------------------------------------------------------------------------------------------------------
// the floating action bar of focus mode
// ---------------------------------------------------------------------------------------------------------

/// The reader's bars are hidden while a selection or an edit is open; this small bar floats at the bottom with
/// what can be done now.
class ReaderActionBar extends StatelessWidget {
  const ReaderActionBar({super.key, required this.background, required this.foreground, required this.children});

  final Color background;
  final Color foreground;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      elevation: 6,
      borderRadius: BorderRadius.circular(28),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: DefaultTextStyle.merge(
          style: TextStyle(color: foreground),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 2,
            children: children,
          ),
        ),
      ),
    );
  }
}

class ReaderActionButton extends StatelessWidget {
  const ReaderActionButton({super.key, required this.label, required this.onPressed, this.color, this.strong = false});

  final String label;
  final VoidCallback? onPressed;
  final Color? color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
      child: Text(label, style: TextStyle(fontWeight: strong ? FontWeight.w800 : FontWeight.w600, fontSize: 14)),
    );
  }
}


// ---------------------------------------------------------------------------------------------------------
// the selection bar's buttons: four compact pills in a 2 x 2 grid, in the app's own button style
// ---------------------------------------------------------------------------------------------------------

/// The colours of the selection buttons: the app's own gradients (violet and saffron, the same as Books and Expeditions)
/// and a soft medium red. They look the same in Light, Dark and Sepia (each button carries its own background, like every
/// gradient tile in the app) and the label is always the app's ink colour, at least 4.5:1 on the whole gradient.
enum ReaderPillTone { purple, red, gold }

extension ReaderPillToneX on ReaderPillTone {
  /// The tile gradient of the tone (light to deeper, 135 degrees like the other gradient tiles).
  LinearGradient get gradient => switch (this) {
        ReaderPillTone.purple => FolkGradients.violet,
        ReaderPillTone.red => const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFFB5AA), Color(0xFFEE7872)]),
        ReaderPillTone.gold => FolkGradients.saffron,
      };

  /// The label: the ink colour on every gradient.
  Color get label => FolkColors.onGradient;
}

/// A compact pill button: the app's button radius and chip typography, a theme gradient, a soft shadow and the app's
/// own press feedback (`PressScale`). 44 dp tall (and at least 44 wide), growing with large text.
class ReaderPillButton extends StatelessWidget {
  const ReaderPillButton({super.key, required this.label, required this.tone, required this.onPressed});

  /// The tap target of a selection button (the bar is compact; 44 dp is the Material minimum).
  static const double minHeight = 44;

  final String label;
  final ReaderPillTone tone;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final text = context.folkText;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onPressed,
          child: Container(
            constraints: const BoxConstraints(minHeight: minHeight, minWidth: minHeight),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(FolkShape.buttonRadius),
              gradient: tone.gradient,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .14), blurRadius: 6, offset: const Offset(0, 2))],
            ),
            child: Opacity(
              opacity: enabled ? 1 : .5,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.chip.copyWith(color: tone.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// While a selection is open: Sentence and Paragraph (violet) on top, Cancel (red) and Highlight (gold) below.
class ReaderSelectionBar extends StatelessWidget {
  const ReaderSelectionBar({
    super.key,
    required this.background,
    required this.onSentence,
    required this.onParagraph,
    required this.onCancel,
    required this.onHighlight,
  });

  final Color background;
  final VoidCallback onSentence;
  final VoidCallback onParagraph;
  final VoidCallback onCancel;
  final VoidCallback onHighlight;

  @override
  Widget build(BuildContext context) {
    Widget cell(Key key, String label, ReaderPillTone tone, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: ReaderPillButton(key: key, label: label, tone: tone, onPressed: onTap),
          ),
        );
    return Material(
      color: background,
      elevation: 3,
      borderRadius: BorderRadius.circular(24),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              cell(const ValueKey('sel-sentence'), 'Sentence', ReaderPillTone.purple, onSentence),
              cell(const ValueKey('sel-paragraph'), 'Paragraph', ReaderPillTone.purple, onParagraph),
            ]),
            Row(children: [
              cell(const ValueKey('sel-cancel'), 'Cancel', ReaderPillTone.red, onCancel),
              cell(const ValueKey('sel-highlight'), 'Highlight', ReaderPillTone.gold, onHighlight),
            ]),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------
// the category + note panel
// ---------------------------------------------------------------------------------------------------------

/// What the panel returns.
typedef HighlightChoice = ({HighlightCategory category, String note});

/// The bottom sheet: choose GOOD / EXCELLENT / RARE and write an optional note (no length limit; it scrolls),
/// then Submit - or Cancel, which saves nothing. [showCategory] / [showNote] let "Edit note" and "Change
/// category" reuse the same panel with only their part.
Future<HighlightChoice?> showHighlightSheet(
  BuildContext context, {
  required Color chrome,
  required Color onChrome,
  required Color secondary,
  HighlightCategory? initialCategory,
  String initialNote = '',
  String title = 'Highlight',
  String submitLabel = 'Submit',
  bool showCategory = true,
  bool showNote = true,
}) {
  return showModalBottomSheet<HighlightChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: chrome,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FolkShape.cardRadius))),
    builder: (sheetContext) => _HighlightSheet(
      chrome: chrome,
      onChrome: onChrome,
      secondary: secondary,
      initialCategory: initialCategory,
      initialNote: initialNote,
      title: title,
      submitLabel: submitLabel,
      showCategory: showCategory,
      showNote: showNote,
    ),
  );
}

class _HighlightSheet extends StatefulWidget {
  const _HighlightSheet({
    required this.chrome,
    required this.onChrome,
    required this.secondary,
    required this.initialCategory,
    required this.initialNote,
    required this.title,
    required this.submitLabel,
    required this.showCategory,
    required this.showNote,
  });

  final Color chrome;
  final Color onChrome;
  final Color secondary;
  final HighlightCategory? initialCategory;
  final String initialNote;
  final String title;
  final String submitLabel;
  final bool showCategory;
  final bool showNote;

  @override
  State<_HighlightSheet> createState() => _HighlightSheetState();
}

class _HighlightSheetState extends State<_HighlightSheet> {
  late HighlightCategory? _category = widget.initialCategory;
  late final TextEditingController _note = TextEditingController(text: widget.initialNote);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Widget _tile(HighlightCategory c) {
    final text = context.folkText;
    final color = Color(c.argb);
    final selected = _category == c;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: c.label,
        excludeSemantics: true,
        child: GestureDetector(
          key: ValueKey('highlight-category-${c.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _category = c),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
            decoration: BoxDecoration(
              color: Color(c.tintArgb),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color, width: selected ? 3 : 1.2),
              boxShadow: c.glows ? [BoxShadow(color: color.withValues(alpha: selected ? c.glowAlpha * 1.5 : c.glowAlpha), blurRadius: selected ? 14 : 9)] : null,
            ),
            alignment: Alignment.center,
            child: Text(
              c.label.toUpperCase(),
              textAlign: TextAlign.center,
              style: text.label.copyWith(color: widget.onChrome, fontWeight: selected ? FontWeight.w800 : FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final canSubmit = !widget.showCategory || _category != null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: text.topBarTitle.copyWith(color: widget.onChrome)),
            if (widget.showCategory) ...[
              const SizedBox(height: 16),
              Text('Category', style: text.caption.copyWith(color: widget.secondary)),
              const SizedBox(height: 8),
              Row(children: [for (final c in HighlightCategory.values) _tile(c)]),
            ],
            if (widget.showNote) ...[
              const SizedBox(height: 16),
              Text('Note (optional)', style: text.caption.copyWith(color: widget.secondary)),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('highlight-note'),
                controller: _note,
                // No length limit: it grows to eight lines, then scrolls inside the box.
                minLines: 3,
                maxLines: 8,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                style: text.body.copyWith(color: widget.onChrome),
                cursorColor: widget.onChrome,
                decoration: InputDecoration(
                  hintText: 'Write your thoughts about this passage',
                  hintStyle: text.body.copyWith(color: widget.secondary),
                  filled: true,
                  fillColor: widget.onChrome.withValues(alpha: .06),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('highlight-cancel'),
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(FolkShape.buttonHeight),
                      foregroundColor: widget.onChrome,
                      side: BorderSide(color: widget.onChrome.withValues(alpha: .4)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    key: const ValueKey('highlight-submit'),
                    onPressed: canSubmit
                        ? () => Navigator.pop<HighlightChoice>(context, (category: _category ?? widget.initialCategory ?? HighlightCategory.good, note: _note.text.trim()))
                        : null,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(FolkShape.buttonHeight),
                      backgroundColor: widget.onChrome,
                      foregroundColor: widget.chrome,
                    ),
                    child: Text(widget.submitLabel),
                  ),
                ),
              ],
            ),
            if (!canSubmit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Choose a category to continue', style: text.caption.copyWith(color: widget.secondary)),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------------------
// the dialog of an existing highlight
// ---------------------------------------------------------------------------------------------------------

enum HighlightAction { editNote, changeCategory }

/// A tap on a highlight: its category and note (long notes scroll), with Edit note and Change category.
/// Tapping outside closes it and the reader carries on.
Future<HighlightAction?> showHighlightInfo(
  BuildContext context, {
  required BookHighlight highlight,
  required Color chrome,
  required Color onChrome,
  required Color secondary,
}) {
  return showDialog<HighlightAction>(
    context: context,
    builder: (dialogContext) {
      final text = dialogContext.folkText;
      final color = Color(highlight.category.argb);
      final maxNote = MediaQuery.of(dialogContext).size.height * .4;
      return Dialog(
        backgroundColor: chrome,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                key: const ValueKey('highlight-info-category'),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Color(highlight.category.tintArgb),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: color, width: 1.4),
                  boxShadow: highlight.category.glows ? [BoxShadow(color: color.withValues(alpha: highlight.category.glowAlpha), blurRadius: 10)] : null,
                ),
                child: Text(highlight.category.label.toUpperCase(), style: text.label.copyWith(color: onChrome, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxNote),
                child: SingleChildScrollView(
                  child: Text(
                    highlight.note.isEmpty ? 'No note yet.' : highlight.note,
                    key: const ValueKey('highlight-info-note'),
                    style: text.body.copyWith(color: highlight.note.isEmpty ? secondary : onChrome, height: 1.45),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  TextButton(
                    key: const ValueKey('highlight-edit-note'),
                    onPressed: () => Navigator.pop(dialogContext, HighlightAction.editNote),
                    style: TextButton.styleFrom(foregroundColor: onChrome, minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget)),
                    child: const Text('Edit note'),
                  ),
                  TextButton(
                    key: const ValueKey('highlight-change-category'),
                    onPressed: () => Navigator.pop(dialogContext, HighlightAction.changeCategory),
                    style: TextButton.styleFrom(foregroundColor: onChrome, minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget)),
                    child: const Text('Change category'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// The colour used for an unfinished selection's handles and neutral tint, from the page's text colour.
Color selectionTint(Color pageText) => pageText.withValues(alpha: .18);

/// The handle colour: the category's colour, or the app's violet while a selection has no category yet.
Color handleColor(HighlightCategory? c) => c == null ? FolkCalendarTokens.selectedRing : Color(c.argb);
