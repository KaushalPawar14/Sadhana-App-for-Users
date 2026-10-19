import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/Commitments.dart';

/// What the student chose. [rounds] is null when the chanting commitment was not
/// asked (the mandatory reading-only prompt) - the caller then leaves it alone.
class CommitmentChoice {
  const CommitmentChoice({this.rounds, required this.readingMinutes});
  final int? rounds;
  final int readingMinutes;
}

const String kReadingCommitmentPrompt =
    "Please set your daily reading commitment (in minutes). If you're a "
    "beginner you can enter 0 — but reading helps you chant with quality.";

/// Both commitments, edited together from the Profile ("Commitment: 16 rounds ·
/// 30 min reading"), or - [mandatory] - only the reading one, which cannot be
/// dismissed (shown once to a student who has not set it yet). 0 is a valid
/// reading commitment.
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
  late final TextEditingController _rounds = TextEditingController(
      text: widget.mandatory ? '' : widget.current.rounds.toString());
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
    final rounds = widget.mandatory ? null : int.tryParse(_rounds.text.trim());
    final reading = parseReadingCommitment(_reading.text);
    setState(() {
      _roundsError = !widget.mandatory && (rounds == null || rounds <= 0)
          ? 'Enter a whole number greater than 0'
          : null;
      _readingError =
          reading == null ? 'Enter minutes from 0 to $kMaxReadingCommitment' : null;
    });
    if (_roundsError != null || _readingError != null) return;
    Navigator.of(context).pop(CommitmentChoice(rounds: rounds, readingMinutes: reading!));
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
    return PopScope(
      canPop: !widget.mandatory,
      child: AlertDialog(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(FolkShape.cardRadius)),
        title: Text(widget.mandatory ? 'Reading commitment' : 'Your commitment',
            style: text.topBarTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.mandatory) ...[
                Text(kReadingCommitmentPrompt, style: text.body),
                const SizedBox(height: FolkSpace.md),
              ] else ...[
                TextField(
                  key: const ValueKey('commitment-rounds'),
                  controller: _rounds,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: text.body,
                  cursorColor: colors.text,
                  decoration: _decoration(context, 'e.g. 16', 'Rounds per day', _roundsError),
                ),
                const SizedBox(height: FolkSpace.md),
              ],
              TextField(
                key: const ValueKey('commitment-reading'),
                controller: _reading,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: widget.mandatory,
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
      'readingCommitmentMinutes': choice.readingMinutes,
    }, SetOptions(merge: true));
    return true;
  } catch (_) {
    return false;
  }
}

/// Once per app open: a student who has not set a reading commitment gets the
/// non-dismissible prompt until they save one (0 is allowed). Stops asking when
/// the save succeeds; asks again if the save fails.
bool _askedThisSession = false;

Future<void> askForReadingCommitmentIfMissing(BuildContext context,
    {Future<Commitments> Function()? load,
    Future<bool> Function(CommitmentChoice)? save}) async {
  if (_askedThisSession) return;
  final current = await (load ?? _loadForPrompt)();
  if (current.readingSet) return;
  if (!context.mounted) return;
  _askedThisSession = true;
  while (context.mounted) {
    final choice =
        await showCommitmentDialog(context, current: current, mandatory: true);
    if (choice == null) continue; // cannot happen (not dismissible); asks again
    if (await (save ?? saveCommitments)(choice)) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save your commitment — try again')));
  }
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
