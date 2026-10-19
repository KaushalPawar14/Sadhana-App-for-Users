import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/Commitments.dart';

/// What the student chose. A field that was not asked (the mandatory prompt asks only for what is
/// missing) is null: the caller then leaves it alone.
class CommitmentChoice {
  const CommitmentChoice({this.rounds, this.readingMinutes});
  final int? rounds;
  final int? readingMinutes;
}

const String kReadingCommitmentPrompt =
    "Please set your daily reading commitment (in minutes). If you're a "
    "beginner you can enter 0 — but reading helps you chant with quality.";

const String kChantCommitmentPrompt =
    'Please set your daily chanting commitment: how many rounds you commit to chant each day (1 or more).';

/// The words of the mandatory box for whatever is missing.
String commitmentPrompt({required bool needRounds, required bool needReading}) {
  if (needRounds && needReading) {
    return 'Please set your daily commitments. Chanting: the rounds you commit to chant each day (1 or more). '
        "Reading: the minutes you commit to read each day — if you're a beginner you can enter 0, "
        'but reading helps you chant with quality.';
  }
  return needRounds ? kChantCommitmentPrompt : kReadingCommitmentPrompt;
}

/// Both commitments, edited together from the Profile ("Commitment: 16 rounds · 30 min reading"), or
/// - [mandatory] - only what is still missing, in a box that cannot be dismissed (shown on app open and
/// before a sadhana report is filed). Chanting is a whole number of 1 or more; 0 is a valid reading
/// commitment.
Future<CommitmentChoice?> showCommitmentDialog(
  BuildContext context, {
  required Commitments current,
  bool mandatory = false,
}) {
  return showDialog<CommitmentChoice>(
    context: context,
    barrierDismissible: !mandatory,
    builder: (_) => _CommitmentDialog(current: current, mandatory: mandatory),
  );
}

class _CommitmentDialog extends StatefulWidget {
  const _CommitmentDialog({required this.current, required this.mandatory});
  final Commitments current;
  final bool mandatory;

  @override
  State<_CommitmentDialog> createState() => _CommitmentDialogState();
}

class _CommitmentDialogState extends State<_CommitmentDialog> {
  bool get _askRounds => !widget.mandatory || !widget.current.roundsSet;
  bool get _askReading => !widget.mandatory || !widget.current.readingSet;

  late final TextEditingController _rounds = TextEditingController(
      text: widget.current.roundsSet ? widget.current.rounds.toString() : '');
  late final TextEditingController _reading = TextEditingController(
      text: widget.current.readingMinutes?.toString() ?? '');
  String? _roundsError;
  String? _readingError;

  @override
  void dispose() {
    _rounds.dispose();
    _reading.dispose();
    super.dispose();
  }

  void _save() {
    final rounds = _askRounds ? parseChantCommitment(_rounds.text) : null;
    final reading = _askReading ? parseReadingCommitment(_reading.text) : null;
    setState(() {
      _roundsError = _askRounds && rounds == null ? 'Enter a whole number of rounds, 1 or more' : null;
      _readingError =
          _askReading && reading == null ? 'Enter minutes from 0 to $kMaxReadingCommitment' : null;
    });
    if (_roundsError != null || _readingError != null) return;
    Navigator.of(context).pop(CommitmentChoice(rounds: rounds, readingMinutes: reading));
  }

  InputDecoration _decoration(BuildContext context, String hint, String label, String? error) {
    final colors = context.folk;
    final text = context.folkText;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      errorText: error,
      labelStyle: text.body.copyWith(color: colors.mutedText),
      hintStyle: text.body.copyWith(color: colors.mutedText),
      filled: true,
      fillColor: colors.surfaceSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        borderSide: BorderSide.none,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final title = !widget.mandatory
        ? 'Your commitment'
        : (_askRounds && _askReading ? 'Your commitments' : (_askRounds ? 'Chanting commitment' : 'Reading commitment'));
    return PopScope(
      canPop: !widget.mandatory,
      child: AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
        title: Text(title, style: text.topBarTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.mandatory) ...[
                Text(commitmentPrompt(needRounds: _askRounds, needReading: _askReading), style: text.body),
                const SizedBox(height: FolkSpace.md),
              ],
              if (_askRounds) ...[
                TextField(
                  key: const ValueKey('commitment-rounds'),
                  controller: _rounds,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: widget.mandatory && _askRounds,
                  style: text.body,
                  cursorColor: colors.text,
                  decoration: _decoration(context, 'e.g. 16', 'Rounds per day', _roundsError),
                ),
                const SizedBox(height: FolkSpace.md),
              ],
              if (_askReading)
                TextField(
                  key: const ValueKey('commitment-reading'),
                  controller: _reading,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  autofocus: widget.mandatory && !_askRounds,
                  style: text.body,
                  cursorColor: colors.text,
                  decoration: _decoration(context, 'e.g. 30, or 0', 'Reading minutes per day', _readingError),
                ),
            ],
          ),
        ),
        actions: [
          if (!widget.mandatory)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
                foregroundColor: colors.mutedText,
                textStyle: text.chip,
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
              backgroundColor: colors.primaryBg,
              foregroundColor: colors.primaryFg,
              elevation: 0,
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              textStyle: text.button,
            ),
            onPressed: _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Writes the chosen commitment(s) to the student's own profile (only these fields,
/// merged). Returns false when the save failed.
Future<bool> saveCommitments(CommitmentChoice choice, {String? uid}) async {
  try {
    final id = uid ?? FirebaseAuth.instance.currentUser?.uid;
    if (id == null) return false;
    await FirebaseFirestore.instance.collection('users').doc(id).set({
      if (choice.rounds != null) 'commitmentRounds': choice.rounds,
      if (choice.readingMinutes != null) 'readingCommitmentMinutes': choice.readingMinutes,
    }, SetOptions(merge: true));
    return true;
  } catch (_) {
    return false;
  }
}

/// Asks (non-dismissible) for whatever is missing in [current] until it is saved, and returns the
/// commitments with it filled in. Asks again if a save fails. Nothing is asked when [current] is complete.
Future<Commitments> ensureCommitments(
  BuildContext context,
  Commitments current, {
  Future<bool> Function(CommitmentChoice)? save,
}) async {
  var now = current;
  while (!now.complete && context.mounted) {
    final choice = await showCommitmentDialog(context, current: now, mandatory: true);
    if (choice == null) continue; // cannot happen (not dismissible); asks again
    if (await (save ?? saveCommitments)(choice)) {
      now = Commitments(
        rounds: choice.rounds ?? now.rounds,
        roundsSet: now.roundsSet || choice.rounds != null,
        readingMinutes: choice.readingMinutes ?? now.readingMinutes,
      );
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save your commitment — try again')));
    }
  }
  return now;
}

/// On app open: a student who has not set BOTH commitments gets the non-dismissible box for whatever
/// is missing, once per app launch (and again before they file a report, see [ensureCommitments]).
bool _askedThisSession = false;

Future<void> askForCommitmentsIfMissing(BuildContext context,
    {Future<Commitments> Function()? load,
    Future<bool> Function(CommitmentChoice)? save}) async {
  if (_askedThisSession) return;
  final current = await (load ?? _loadForPrompt)();
  if (current.complete) return;
  if (!context.mounted) return;
  _askedThisSession = true;
  await ensureCommitments(context, current, save: save);
}

Future<Commitments> _loadForPrompt() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Commitments(readingMinutes: 0);
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    // Not registered yet (no name): the registration form asks instead.
    if (data == null || (data['name'] ?? '').toString().isEmpty) {
      return const Commitments(readingMinutes: 0);
    }
    return Commitments.fromUser(data);
  } catch (_) {
    return const Commitments(readingMinutes: 0);
  }
}

@visibleForTesting
void resetCommitmentPromptForTests() => _askedThisSession = false;
