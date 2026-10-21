import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookDoubts.dart';
import '../utils/BookHighlights.dart';
import 'GradientActionButton.dart';

// The reader's DOUBT dialogs, drawn in the reading mode's own colours (chrome / onChrome / secondary).

/// The student's choice when asking: the question and who it goes to ("ai" or "guide").
typedef DoubtAsk = ({String question, String mode});

const String kDoubtQuestionLabel = 'What is your doubt about this passage?';

/// How long the ask dialog takes to open (a gentle fade with a slight scale and rise); instant with "reduce animations".
const Duration kDoubtDialogOpen = Duration(milliseconds: 200);

/// Opens [builder] as a dialog that fades in with a slight scale and rise over [kDoubtDialogOpen] (instant when the
/// student reduces animations). Same barrier and dismiss behaviour as `showDialog`; the page's theme is carried over.
Future<T?> _showSmoothDialog<T>(BuildContext context, WidgetBuilder builder) {
  final theme = Theme.of(context);
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: FolkMotion.of(context, kDoubtDialogOpen),
    pageBuilder: (ctx, _, __) => Theme(data: theme, child: SafeArea(child: Builder(builder: builder))),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeIn);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, .03), end: Offset.zero).animate(curved),
          child: ScaleTransition(scale: Tween<double>(begin: .96, end: 1).animate(curved), child: child),
        ),
      );
    },
  );
}

/// "Your doubt": the passage, a required question, and Ask guide / Ask AI side by side. Cancel (or tapping outside) saves
/// nothing.
Future<DoubtAsk?> showAskDoubtDialog(
  BuildContext context, {
  required String passage,
  required Color chrome,
  required Color onChrome,
  required Color secondary,
  String title = 'Your doubt',
  String initialQuestion = '',
}) {
  return _showSmoothDialog<DoubtAsk>(
    context,
    (_) => _AskDoubtDialog(passage: passage, chrome: chrome, onChrome: onChrome, secondary: secondary, title: title, initialQuestion: initialQuestion),
  );
}

class _AskDoubtDialog extends StatefulWidget {
  const _AskDoubtDialog({required this.passage, required this.chrome, required this.onChrome, required this.secondary, required this.title, required this.initialQuestion});

  final String passage;
  final Color chrome;
  final Color onChrome;
  final Color secondary;
  final String title;
  final String initialQuestion;

  @override
  State<_AskDoubtDialog> createState() => _AskDoubtDialogState();
}

class _AskDoubtDialogState extends State<_AskDoubtDialog> {
  late final TextEditingController _question = TextEditingController(text: widget.initialQuestion);
  final FocusNode _focus = FocusNode();
  String? _error;
  Animation<double>? _opening;
  bool _focusScheduled = false;

  /// The keyboard opens only once the dialog has finished opening: asking for it during the transition made the dialog
  /// resize while it was still moving (a visible hitch). With "reduce animations" there is no transition to wait for.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_focusScheduled) return;
    _focusScheduled = true;
    final animation = ModalRoute.of(context)?.animation;
    if (animation == null || animation.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
      return;
    }
    _opening = animation..addStatusListener(_focusWhenOpen);
  }

  void _focusWhenOpen(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _opening?.removeStatusListener(_focusWhenOpen);
    if (mounted) _focus.requestFocus();
  }

  @override
  void dispose() {
    _opening?.removeStatusListener(_focusWhenOpen);
    _focus.dispose();
    _question.dispose();
    super.dispose();
  }

  void _send(String mode) {
    final q = _question.text.trim();
    if (q.isEmpty) {
      setState(() => _error = 'Please write your doubt first');
      return;
    }
    Navigator.pop<DoubtAsk>(context, (question: q, mode: mode));
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final gray = Color(HighlightCategory.doubt.argb);
    final p = widget.passage.trim().replaceAll(RegExp(r'\s+'), ' ');
    return Dialog(
      key: const ValueKey('ask-doubt-dialog'),
      backgroundColor: widget.chrome,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
      child: SingleChildScrollView(
        // (No `MediaQuery.of(context)` here: reading the insets would rebuild the whole dialog on every frame of the
        // keyboard's animation. `Dialog` makes room for the keyboard by itself.)
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: text.topBarTitle.copyWith(color: widget.onChrome)),
            const SizedBox(height: 12),
            Container(
              key: const ValueKey('ask-doubt-passage'),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Color(HighlightCategory.doubt.tintArgb),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: gray, width: 1.2),
              ),
              child: Text(p.length > 260 ? '${p.substring(0, 260)}…' : p, maxLines: 5, overflow: TextOverflow.ellipsis, style: text.small.copyWith(color: widget.onChrome, height: 1.4)),
            ),
            const SizedBox(height: 14),
            Text(kDoubtQuestionLabel, style: text.caption.copyWith(color: widget.secondary)),
            const SizedBox(height: 8),
            TextField(
              key: const ValueKey('doubt-question'),
              controller: _question,
              focusNode: _focus,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              style: text.body.copyWith(color: widget.onChrome),
              cursorColor: widget.onChrome,
              decoration: InputDecoration(
                hintText: 'Write your question',
                hintStyle: text.body.copyWith(color: widget.secondary),
                errorText: _error,
                counterText: '',
                filled: true,
                fillColor: widget.onChrome.withValues(alpha: .06),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            _AskButtons(onAskGuide: () => _send('guide'), onAskAi: () => _send('ai')),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const ValueKey('doubt-cancel'),
                onPressed: () => Navigator.pop(context),
                style: TextButton.styleFrom(foregroundColor: widget.secondary, minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget)),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Ask guide" (green) and "Ask AI" (violet, like the AI button) SIDE BY SIDE in one row, equal width. Only when the
/// labels truly cannot fit in half a row at the student's text size do they stack, one under the other (full width).
class _AskButtons extends StatelessWidget {
  const _AskButtons({required this.onAskGuide, required this.onAskAi});

  final VoidCallback onAskGuide;
  final VoidCallback onAskAi;

  static const String guideLabel = 'Ask guide';
  static const String aiLabel = 'Ask AI';
  static const double gap = 10;

  /// The two buttons are 34 dp tall (a compact pair); they grow only when the text size makes the label taller.
  static const double height = 34;
  static const double verticalPadding = 5.5;

  /// The pair is a little narrower than the dialog's content: this much is left empty on each side of the row.
  static const double sideInset = 8;

  /// The dialog's content width (screen - the dialog's 20 dp insets - its 20 dp padding), then half of it, minus the
  /// button's own padding: that is what one label may take. (The width comes from the screen, not from the layout pass.)
  static bool fitsSideBySide(BuildContext context) {
    final inner = MediaQuery.sizeOf(context).width - 2 * 20 - 2 * 20 - 2 * sideInset;
    final room = (inner - gap) / 2 - 2 * GradientActionButton.horizontalPadding;
    final style = context.folkText.button;
    final scaler = MediaQuery.textScalerOf(context);
    var widest = 0.0;
    for (final label in [guideLabel, aiLabel]) {
      final tp = TextPainter(text: TextSpan(text: label, style: style), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)..layout();
      widest = math.max(widest, tp.width);
    }
    return widest <= room;
  }

  @override
  Widget build(BuildContext context) {
    final guide = GradientActionButton(key: const ValueKey('doubt-ask-guide'), label: guideLabel, gradient: FolkGradients.green, minHeight: height, verticalPadding: verticalPadding, onPressed: onAskGuide);
    final ai = GradientActionButton(key: const ValueKey('doubt-ask-ai'), label: aiLabel, gradient: FolkGradients.violet, minHeight: height, verticalPadding: verticalPadding, onPressed: onAskAi);
    if (fitsSideBySide(context)) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: sideInset),
        child: Row(
          key: const ValueKey('doubt-ask-row'),
          // (both labels fit on one line here, so the two buttons are the same height; no `stretch` inside a scroll view)
          children: [Expanded(child: guide), const SizedBox(width: gap), Expanded(child: ai)],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: sideInset),
      child: Column(
        key: const ValueKey('doubt-ask-stack'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [guide, const SizedBox(height: gap), ai],
      ),
    );
  }
}

/// What a tap on a doubt highlight can lead to.
enum DoubtAction { editQuestion, askAi, askGuide, editNote }

/// A tap on a doubt highlight: the question, the answer (live) and who gave it, the student's note, and the actions: edit
/// the question, ask the AI or the guide again, edit the note. Tapping outside closes it.
Future<DoubtAction?> showDoubtDetails(
  BuildContext context, {
  required BookHighlight highlight,
  required DoubtStore store,
  required Color chrome,
  required Color onChrome,
  required Color secondary,
}) {
  return showDialog<DoubtAction>(
    context: context,
    builder: (dialogContext) {
      final text = dialogContext.folkText;
      final gray = Color(HighlightCategory.doubt.argb);
      final maxBody = MediaQuery.of(dialogContext).size.height * .42;

      Widget status(Doubt? d) {
        if (d == null) {
          return Text('Your doubt could not be loaded. Check your connection and open it again.', key: const ValueKey('doubt-info-missing'), style: text.small.copyWith(color: secondary));
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Your doubt', style: text.caption.copyWith(color: secondary)),
            const SizedBox(height: 4),
            Text(d.question, key: const ValueKey('doubt-info-question'), style: text.bodyStrong.copyWith(color: onChrome, height: 1.4)),
            const SizedBox(height: 12),
            if (d.answered) ...[
              Text('Answered by ${d.answeredByLabel}', key: const ValueKey('doubt-info-by'), style: text.caption.copyWith(color: secondary)),
              const SizedBox(height: 4),
              Text(d.answer!, key: const ValueKey('doubt-info-answer'), style: text.body.copyWith(color: onChrome, height: 1.45)),
            ] else
              Text(
                d.toGuide ? 'Waiting for your guide to answer.' : 'Not answered yet. Tap "Ask AI again" to get an answer.',
                key: const ValueKey('doubt-info-pending'),
                style: text.small.copyWith(color: secondary),
              ),
          ],
        );
      }

      return Dialog(
        key: const ValueKey('doubt-info-dialog'),
        backgroundColor: chrome,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
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
                decoration: BoxDecoration(color: Color(HighlightCategory.doubt.tintArgb), borderRadius: BorderRadius.circular(20), border: Border.all(color: gray, width: 1.4)),
                child: Text(HighlightCategory.doubt.label.toUpperCase(), style: text.label.copyWith(color: onChrome, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 14),
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxBody),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StreamBuilder<Doubt?>(stream: store.watch(highlight.id), builder: (context, snap) => status(snap.data)),
                      const SizedBox(height: 12),
                      Text(
                        highlight.note.isEmpty ? 'No note yet.' : highlight.note,
                        key: const ValueKey('highlight-info-note'),
                        style: text.body.copyWith(color: highlight.note.isEmpty ? secondary : onChrome, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: [
                  for (final (key, label, action) in const [
                    ('doubt-edit-question', 'Edit question', DoubtAction.editQuestion),
                    ('doubt-ask-ai-again', 'Ask AI again', DoubtAction.askAi),
                    ('doubt-ask-guide-again', 'Ask guide again', DoubtAction.askGuide),
                    ('highlight-edit-note', 'Edit note', DoubtAction.editNote),
                  ])
                    TextButton(
                      key: ValueKey(key),
                      onPressed: () => Navigator.pop(dialogContext, action),
                      style: TextButton.styleFrom(foregroundColor: onChrome, minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget)),
                      child: Text(label),
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

/// Edit the question of a doubt (required).
Future<String?> showEditQuestionDialog(
  BuildContext context, {
  required String current,
  required Color chrome,
  required Color onChrome,
  required Color secondary,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) {
      final text = dialogContext.folkText;
      final controller = TextEditingController(text: current);
      String? error;
      return StatefulBuilder(
        builder: (context, setState) => Dialog(
          key: const ValueKey('edit-question-dialog'),
          backgroundColor: chrome,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Edit your question', style: text.topBarTitle.copyWith(color: onChrome)),
                const SizedBox(height: 12),
                TextField(
                  key: const ValueKey('edit-question-field'),
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 6,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  style: text.body.copyWith(color: onChrome),
                  cursorColor: onChrome,
                  decoration: InputDecoration(
                    errorText: error,
                    counterText: '',
                    filled: true,
                    fillColor: onChrome.withValues(alpha: .06),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext), style: TextButton.styleFrom(foregroundColor: secondary, minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget)), child: const Text('Cancel')),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      key: const ValueKey('edit-question-save'),
                      onPressed: () {
                        final q = controller.text.trim();
                        if (q.isEmpty) {
                          setState(() => error = 'Please write your doubt first');
                          return;
                        }
                        Navigator.pop(dialogContext, q);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: onChrome, foregroundColor: chrome, minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget)),
                      child: const Text('Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
