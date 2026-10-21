import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookDoubts.dart';
import '../utils/BookHighlights.dart';

// The reader's DOUBT dialogs, drawn in the reading mode's own colours (chrome / onChrome / secondary).

/// The student's choice when asking: the question and who it goes to ("ai" or "guide").
typedef DoubtAsk = ({String question, String mode});

const String kDoubtQuestionLabel = 'What is your doubt about this passage?';

/// "Your doubt": the passage, a required question, and Ask AI / Ask guide. Cancel (or tapping outside) saves nothing.
Future<DoubtAsk?> showAskDoubtDialog(
  BuildContext context, {
  required String passage,
  required Color chrome,
  required Color onChrome,
  required Color secondary,
  String title = 'Your doubt',
  String initialQuestion = '',
}) {
  return showDialog<DoubtAsk>(
    context: context,
    builder: (_) => _AskDoubtDialog(passage: passage, chrome: chrome, onChrome: onChrome, secondary: secondary, title: title, initialQuestion: initialQuestion),
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
  String? _error;

  @override
  void dispose() {
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
        padding: EdgeInsets.fromLTRB(20, 20, 20, 14 + MediaQuery.of(context).viewInsets.bottom * 0),
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
              autofocus: true,
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
            SizedBox(
              height: FolkShape.buttonHeight,
              child: ElevatedButton(
                key: const ValueKey('doubt-ask-ai'),
                onPressed: () => _send('ai'),
                style: ElevatedButton.styleFrom(backgroundColor: widget.onChrome, foregroundColor: widget.chrome, shape: const StadiumBorder()),
                child: const Text('Ask AI'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: FolkShape.buttonHeight,
              child: OutlinedButton(
                key: const ValueKey('doubt-ask-guide'),
                onPressed: () => _send('guide'),
                style: OutlinedButton.styleFrom(foregroundColor: widget.onChrome, side: BorderSide(color: widget.onChrome.withValues(alpha: .5)), shape: const StadiumBorder()),
                child: const Text('Ask guide'),
              ),
            ),
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
