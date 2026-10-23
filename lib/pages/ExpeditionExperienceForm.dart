import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/ExpeditionExperience.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';

/// Share what a trip meant to you (Master 2 B).
///
/// Opened from the push "Share your experience of (the trip)", or from the card at
/// the top of Expeditions. Three questions and a free-text note, editable for
/// seven days from the request.
///
/// It is read and written ONLY here, and only while the window is open. It is
/// not shown on the student's profile, and once the window closes this screen
/// shows nothing of what they wrote — it was written for their guides.
///
/// The server creates the document; the student only fills it in. The rules
/// allow an update of the answer fields on the student's own document inside
/// the window, so there is nothing here the student could do to extend it.
class ExpeditionExperienceForm extends StatefulWidget {
  const ExpeditionExperienceForm({
    super.key,
    required this.uid,
    required this.tripId,
    this.tripName = '',
    this.firestore,
  });

  final String uid;
  final String tripId;

  /// From the push, used only if the document cannot be read.
  final String tripName;

  /// Test seam: the app never sets this.
  final FirebaseFirestore? firestore;

  @override
  State<ExpeditionExperienceForm> createState() =>
      _ExpeditionExperienceFormState();
}

class _ExpeditionExperienceFormState extends State<ExpeditionExperienceForm> {
  FirebaseFirestore get _firestore =>
      widget.firestore ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> get _ref => _firestore
      .collection('expeditionExperiences')
      .doc('${widget.tripId}_${widget.uid}');

  final Map<String, TextEditingController> _controllers = {
    for (final f in const ['learned', 'touched', 'change', 'notes'])
      f: TextEditingController(),
  };

  ExperienceRequest? _request;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  String? _problem;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final snap = await _ref.get();
      final data = snap.data();
      // Someone else's, or not one the server asked for: nothing to show. The
      // rules would refuse the read anyway; this keeps the screen honest.
      final mine = data != null && (data['studentUid'] ?? '') == widget.uid;
      final request = mine ? ExperienceRequest.from(snap.id, data) : null;
      if (request != null && request.isOpen()) {
        for (final e in _controllers.entries) {
          e.value.text = request.answer(e.key);
        }
      }
      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Map<String, String> get _answers => {
        for (final e in _controllers.entries) e.key: e.value.text.trim(),
      };

  Future<void> _save() async {
    final request = _request;
    if (request == null) return;
    if (!hasAnyAnswer(_answers)) {
      setState(() => _problem = 'Please write something before you share it');
      return;
    }
    // The window may have closed while the form was open. The rules would refuse
    // the write; say so plainly instead of showing an error.
    if (!request.isOpen()) {
      setState(() {
        _problem = null;
        _request = request; // rebuilds into the closed state
      });
      return;
    }

    setState(() {
      _saving = true;
      _problem = null;
    });
    try {
      await _ref.update({
        ..._answers,
        'status': 'submitted',
        // First time only is the interesting one, but the rules allow either;
        // the guide's "Shared 22 Oct" is the day it was first shared.
        if (!request.submitted) 'submittedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thank you, Prabhu 🙏 Your guide will read it')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _problem = "Couldn't save just now. Check your connection and try again.";
      });
    }
  }

  Widget _closed(String message) {
    final text = context.folkText;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(message, textAlign: TextAlign.center, style: text.body),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;

    Widget body;
    if (_loading) {
      body = const GhostScope(
        child: Padding(
          padding: EdgeInsets.all(FolkSpace.pagePadding),
          child: GhostPlaceholder(
              width: double.infinity, height: 220, showBars: false),
        ),
      );
    } else if (_failed) {
      body = FolkErrorRetry(
        message: "Couldn't open this just now.",
        onRetry: _load,
      );
    } else if (_request == null) {
      body = _closed("There's nothing to share here right now.");
    } else if (!_request!.isOpen()) {
      body = _closed(
          'The time to share this has passed. Thank you for taking part 🙏');
    } else {
      final request = _request!;
      final name = request.tripName.isNotEmpty
          ? request.tripName
          : (widget.tripName.isNotEmpty ? widget.tripName : 'your trip');
      body = SingleChildScrollView(
        padding: const EdgeInsets.all(FolkSpace.pagePadding),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Your experience of $name', style: text.bodyStrong),
            const SizedBox(height: 4),
            Text(
              '${request.untilLine}. Your guide reads this — it is not shown '
              'on your profile.',
              style: text.small,
            ),
            const SizedBox(height: 16),
            for (final q in kExperienceQuestions) ...[
              Text(q.question, style: text.bodyStrong),
              const SizedBox(height: 6),
              TextField(
                key: ValueKey('experience-${q.field}'),
                controller: _controllers[q.field],
                minLines: 3,
                maxLines: 8,
                textCapitalization: TextCapitalization.sentences,
                inputFormatters: [
                  LengthLimitingTextInputFormatter(kExperienceMaxChars),
                ],
                onChanged: (_) {
                  if (_problem != null) setState(() => _problem = null);
                },
                style: text.body,
                cursorColor: colors.text,
                decoration: FolkDialog.field(context, hint: 'Write here…')
                    .copyWith(alignLabelWithHint: true, counterText: ''),
              ),
              const SizedBox(height: 16),
            ],
            Text('Anything else you would like to say?', style: text.bodyStrong),
            const SizedBox(height: 6),
            TextField(
              key: const ValueKey('experience-notes'),
              controller: _controllers['notes'],
              minLines: 2,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              inputFormatters: [
                LengthLimitingTextInputFormatter(kExperienceMaxChars),
              ],
              style: text.body,
              cursorColor: colors.text,
              decoration: FolkDialog.field(context, hint: 'Optional')
                  .copyWith(alignLabelWithHint: true, counterText: ''),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 12),
              Text(_problem!,
                  key: const ValueKey('experience-problem'),
                  style: text.small.copyWith(color: colors.calendarMissedText)),
            ],
            const SizedBox(height: 20),
            PrimaryButton(
              label: request.submitted ? 'Save changes' : 'Share',
              loading: _saving,
              onPressed: _saving ? null : _save,
            ),
          ],
        ),
      );
    }

    return FolkScaffold(title: 'Share your experience', body: body);
  }
}

/// The card at the top of Expeditions for a request that is still open.
class ExperienceRequestCard extends StatelessWidget {
  const ExperienceRequestCard({
    super.key,
    required this.request,
    required this.onOpen,
  });

  final ExperienceRequest request;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final name = request.tripName.isNotEmpty ? request.tripName : 'your trip';
    return FolkCard(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.submitted
                ? 'Your experience of $name'
                : 'Share your experience of $name',
            style: text.bodyStrong,
          ),
          const SizedBox(height: 4),
          Text(request.untilLine, style: text.small),
          const SizedBox(height: 12),
          PrimaryButton(
            label: request.submitted ? 'Edit' : 'Share',
            onPressed: onOpen,
          ),
        ],
      ),
    );
  }
}
