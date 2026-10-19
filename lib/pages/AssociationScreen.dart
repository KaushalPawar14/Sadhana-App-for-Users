import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/FolkErrorRetry.dart';
import 'package:intl/intl.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SeenMarkers.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';

/// Association — meeting requests between a student and their guide.
///
/// Firestore: `associations` (auto-id), one document per meeting.
/// The guide's FCM token lives at `adminUsers/{guideId}.fcmToken` — the
/// same location `services/SendNotifications.dart` used before it was
/// deleted (2026-09-03); that file is gone, this comment just records
/// where the convention came from.
class AssociationScreen extends StatefulWidget {
  final String uid;
  final String userName;
  final String role;

  const AssociationScreen({
    super.key,
    required this.uid,
    required this.userName,
    required this.role,
  });

  @override
  State<AssociationScreen> createState() => _AssociationScreenState();
}

class _AssociationScreenState extends State<AssociationScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _guideId = '';
  String _studentName = '';

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) —
  /// `_buildMeetings()` used to construct this fresh every time it was
  /// called from `build()`. Hoisted to a field, built once in `initState()`
  /// — safe unconditionally: `widget.uid` is fixed for this screen's whole
  /// life (a pushed, single-student route; nothing ever rebuilds this
  /// widget with a different `uid`).
  late Stream<QuerySnapshot<Map<String, dynamic>>> _meetingsStream;

  @override
  void initState() {
    super.initState();
    _meetingsStream = _firestore
        .collection('associations')
        .where('studentUid', isEqualTo: widget.uid)
        .snapshots();
    _loadProfile();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // associations.
    SeenMarkers.markSeen(widget.uid, 'associations');
  }

  /// The guide who owns this student decides where the request is routed.
  Future<void> _loadProfile() async {
    try {
      final doc = await _firestore.collection('users').doc(widget.uid).get();
      final data = doc.data();
      if (!mounted || data == null) return;

      setState(() {
        _guideId = (data['guideId'] ?? '').toString();
        _studentName = widget.userName.isNotEmpty
            ? widget.userName
            : (data['name'] ?? '').toString();
      });
    } catch (_) {
      // Request submission re-checks before writing.
    }
  }

  // ---------------------------------------------------------------------------
  // Request sheet
  // ---------------------------------------------------------------------------

  Future<void> _openRequestSheet() async {
    if (_guideId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "No guide is assigned to you yet. Ask your guide to add you first.",
          ),
        ),
      );
      return;
    }

    DateTime? pickedDate;
    TimeOfDay? pickedTime;
    String notes = '';
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = context.folk;
            final textStyles = context.folkText;
            Future<void> submit() async {
              if (pickedDate == null || pickedTime == null) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text("Please choose a date and time"),
                  ),
                );
                return;
              }

              setSheetState(() => saving = true);

              final preferred = DateTime(
                pickedDate!.year,
                pickedDate!.month,
                pickedDate!.day,
                pickedTime!.hour,
                pickedTime!.minute,
              );

              try {
                await _firestore.collection('associations').add({
                  'studentUid': widget.uid,
                  'studentName': _studentName,
                  'guideId': _guideId,
                  'requestedBy': 'student',
                  'preferredDate': Timestamp.fromDate(preferred),
                  'confirmedDate': null,
                  'status': 'pending',
                  'studentNotes': notes.trim(),
                  'guideNotes': '',
                  'createdAt': FieldValue.serverTimestamp(),
                  'updatedAt': FieldValue.serverTimestamp(),
                });

                // The guide is notified server-side by
                // `functions/associationNotify.js`, reacting to this same
                // write — no client-side send any more (task: "Remove the
                // embedded service-account key from the Student app").

                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Meeting request sent")),
                );
              } catch (_) {
                setSheetState(() => saving = false);
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text("Could not send request")),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(FolkShape.cardRadius)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.surfaceSecondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "Request a Meeting",
                      style: textStyles.topBarTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text("With $_guideId", style: textStyles.small),
                    const SizedBox(height: 20),
                    _pickerRow(
                      icon: Icons.calendar_today,
                      label: "Preferred date",
                      value: pickedDate == null
                          ? "Not set"
                          : DateFormat('dd MMM yyyy').format(pickedDate!),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: now,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() => pickedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _pickerRow(
                      icon: Icons.access_time,
                      label: "Preferred time",
                      value: pickedTime == null
                          ? "Not set"
                          : pickedTime!.format(sheetContext),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetContext,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => pickedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      maxLines: 3,
                      onChanged: (v) => notes = v,
                      style: textStyles.body,
                      cursorColor: colors.text,
                      decoration: FolkDialog.field(context,
                              label: "Reason / Message (optional)")
                          .copyWith(alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: "Submit Request",
                      loading: saving,
                      onPressed: saving ? null : submit,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _pickerRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final colors = context.folk;
    final text = context.folkText;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
      child: Container(
        constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: colors.surfaceSecondary,
          borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: colors.mutedText),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, style: text.bodyStrong),
            ),
            Text(
              value,
              style: text.body.copyWith(
                color: value == "Not set" ? colors.mutedText : colors.text,
                fontWeight:
                    value == "Not set" ? FontWeight.normal : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Meeting list
  // ---------------------------------------------------------------------------

  // Confirmed = green, cancelled = coral, completed = violet, pending = saffron.
  static ({FolkGradientStyle style, String label}) _statusStyle(String status) {
    switch (status) {
      case 'confirmed':
        return (style: FolkGradientStyle.green, label: 'Confirmed');
      case 'cancelled':
        return (style: FolkGradientStyle.coral, label: 'Cancelled');
      case 'completed':
        return (style: FolkGradientStyle.violet, label: 'Completed');
      default:
        return (style: FolkGradientStyle.saffron, label: 'Pending');
    }
  }

  Widget _meetingCard(String docId, Map<String, dynamic> data) {
    final status = (data['status'] ?? 'pending').toString();
    final style = _statusStyle(status);

    final confirmed = data['confirmedDate'];
    final preferred = data['preferredDate'];
    final shown = confirmed is Timestamp
        ? confirmed
        : (preferred is Timestamp ? preferred : null);

    final studentNotes = (data['studentNotes'] ?? '').toString();
    final guideNotes = (data['guideNotes'] ?? '').toString();
    final guideId = (data['guideId'] ?? '').toString();

    final isCounter = data['isCounterProposal'] == true;
    final counterNote = (data['counterProposalNote'] ?? '').toString();
    final counterDate = data['counterProposalDate'];

    // The student only acts on meetings the guide started and that are still
    // awaiting a reply. Once a counter-proposal is sent, the guide responds.
    final needsStudentReply = status == 'pending' &&
        (data['requestedBy'] ?? '').toString() == 'guide' &&
        !isCounter;

    final colors = context.folk;
    final text = context.folkText;

    return Container(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      padding: const EdgeInsets.all(FolkSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        boxShadow: colors.cardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  shown == null
                      ? "Date not set"
                      : DateFormat('dd MMM yyyy, hh:mm a')
                          .format(shown.toDate()),
                  style: text.bodyStrong,
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  gradient: FolkGradients.of(style.style),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  style.label,
                  style: text.caption.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: FolkColors.onGradient,
                  ),
                ),
              ),
            ],
          ),
          if (confirmed is Timestamp && preferred is Timestamp) ...[
            const SizedBox(height: 4),
            Text(
              "Requested: "
              "${DateFormat('dd MMM yyyy, hh:mm a').format(preferred.toDate())}",
              style: text.caption.copyWith(fontSize: 11),
            ),
          ],
          if (guideId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline, size: 16, color: colors.mutedText),
                const SizedBox(width: 5),
                Text(guideId, style: text.small),
              ],
            ),
          ],
          if (studentNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text("Your message: $studentNotes", style: text.small),
          ],
          if (guideNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.surfaceSecondary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                "Guide's notes: $guideNotes",
                style: text.body.copyWith(fontSize: 13),
              ),
            ),
          ],

          /// Counter-proposal the student has already sent.
          if (isCounter) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: FolkGradients.violet,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz,
                          size: 16, color: FolkColors.onGradient),
                      const SizedBox(width: 5),
                      Text(
                        "Counter-proposal sent",
                        style: text.caption.copyWith(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: FolkColors.onGradient,
                        ),
                      ),
                    ],
                  ),
                  if (counterDate is Timestamp) ...[
                    const SizedBox(height: 4),
                    Text(
                      "You proposed: "
                      "${DateFormat('dd MMM yyyy, hh:mm a').format(counterDate.toDate())}",
                      style: text.body
                          .copyWith(fontSize: 13, color: FolkColors.onGradient),
                    ),
                  ],
                  if (counterNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      counterNote,
                      style: text.onGradientSmall,
                    ),
                  ],
                ],
              ),
            ),
          ],

          /// The guide proposed this meeting — the student replies.
          if (needsStudentReply) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _confirmGuideMeeting(docId, data),
                    style: FolkDialog.primaryButton(colors, text).copyWith(
                      minimumSize: const WidgetStatePropertyAll(
                          Size.fromHeight(FolkShape.touchTarget)),
                      padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(horizontal: 8)),
                    ),
                    child: const Text(
                      "Confirm Meeting",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _openCounterProposalSheet(docId, data),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(FolkShape.touchTarget),
                      foregroundColor: colors.text,
                      side: BorderSide(color: colors.mutedText),
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: text.chip,
                    ),
                    child: const Text(
                      "Propose New Time",
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Responding to a guide-initiated meeting
  // ---------------------------------------------------------------------------

  Future<void> _confirmGuideMeeting(
    String docId,
    Map<String, dynamic> data,
  ) async {
    final preferred = data['preferredDate'];

    try {
      await _firestore.collection('associations').doc(docId).update({
        // The guide's proposed slot becomes the confirmed one, so their
        // "Upcoming" list has a date to show.
        'confirmedDate': preferred,
        'status': 'confirmed',
        'updatedAt': FieldValue.serverTimestamp(),
      });

      // The guide is notified server-side by
      // `functions/associationNotify.js`, reacting to this same write — no
      // client-side send any more (task: "Remove the embedded
      // service-account key from the Student app").

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Meeting confirmed")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not confirm meeting")),
      );
    }
  }

  Future<void> _openCounterProposalSheet(
    String docId,
    Map<String, dynamic> data,
  ) async {
    DateTime? pickedDate;
    TimeOfDay? pickedTime;
    String reason = '';
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final colors = context.folk;
            final textStyles = context.folkText;
            Future<void> submit() async {
              if (reason.trim().isEmpty) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text("Please give a reason for the change"),
                  ),
                );
                return;
              }
              if (pickedDate == null || pickedTime == null) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                      content: Text("Please choose a date and time")),
                );
                return;
              }

              setSheetState(() => saving = true);

              final proposed = DateTime(
                pickedDate!.year,
                pickedDate!.month,
                pickedDate!.day,
                pickedTime!.hour,
                pickedTime!.minute,
              );

              try {
                await _firestore.collection('associations').doc(docId).update({
                  'isCounterProposal': true,
                  'counterProposalDate': Timestamp.fromDate(proposed),
                  'counterProposalNote': reason.trim(),
                  'updatedAt': FieldValue.serverTimestamp(),
                  // status intentionally stays "pending" — the guide decides.
                });

                // The guide is notified server-side by
                // `functions/associationNotify.js`, reacting to this same
                // write — no client-side send any more (task: "Remove the
                // embedded service-account key from the Student app").

                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Counter-proposal sent")),
                );
              } catch (_) {
                setSheetState(() => saving = false);
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text("Could not send proposal")),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(FolkShape.cardRadius)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.surfaceSecondary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      "Propose a New Time",
                      style: textStyles.topBarTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      autofocus: true,
                      maxLines: 2,
                      onChanged: (v) => reason = v,
                      style: textStyles.body,
                      cursorColor: colors.text,
                      decoration: FolkDialog.field(context,
                              label: "Reason for change *")
                          .copyWith(alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 14),
                    _pickerRow(
                      icon: Icons.calendar_today,
                      label: "New date",
                      value: pickedDate == null
                          ? "Not set"
                          : DateFormat('dd MMM yyyy').format(pickedDate!),
                      onTap: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: sheetContext,
                          initialDate: now,
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setSheetState(() => pickedDate = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 10),
                    _pickerRow(
                      icon: Icons.access_time,
                      label: "New time",
                      value: pickedTime == null
                          ? "Not set"
                          : pickedTime!.format(sheetContext),
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: sheetContext,
                          initialTime: TimeOfDay.now(),
                        );
                        if (picked != null) {
                          setSheetState(() => pickedTime = picked);
                        }
                      },
                    ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: "Send Proposal",
                      loading: saving,
                      onPressed: saving ? null : submit,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMeetings() {
    return StreamBuilder<QuerySnapshot>(
      stream: _meetingsStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return FolkErrorRetry(
            compact: true,
            message: "Couldn't load your meetings just now.",
            onRetry: () => setState(() {
              _meetingsStream = _firestore
                  .collection('associations')
                  .where('studentUid', isEqualTo: widget.uid)
                  .snapshots();
            }),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Ghost meeting cards while the list loads.
          return const GhostScope(
            child: Column(
              children: [
                GhostPlaceholder(
                    width: double.infinity,
                    height: 110,
                    radius: FolkShape.tileRadius),
                SizedBox(height: FolkSpace.cardGap),
                GhostPlaceholder(
                    width: double.infinity,
                    height: 110,
                    radius: FolkShape.tileRadius),
              ],
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: context.folk.surface,
              borderRadius: BorderRadius.circular(FolkShape.tileRadius),
              boxShadow: context.folk.cardShadows,
            ),
            child: Text("No meetings yet", style: context.folkText.small),
          );
        }

        // Sorted client-side: an orderBy alongside the where would require a
        // composite index.
        final meetings = docs.toList()
          ..sort((a, b) {
            final aData = a.data() as Map<String, dynamic>;
            final bData = b.data() as Map<String, dynamic>;
            final aDate = aData['confirmedDate'] ?? aData['preferredDate'];
            final bDate = bData['confirmedDate'] ?? bData['preferredDate'];
            if (aDate is! Timestamp || bDate is! Timestamp) return 0;
            return bDate.compareTo(aDate); // newest first
          });

        return Column(
          children: meetings
              .map((d) => _meetingCard(d.id, d.data() as Map<String, dynamic>))
              .toList(),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Scaffold
  // ---------------------------------------------------------------------------

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`: no `PopScope`/`WillPopScope`
  /// at all before this fix, so a hardware back press with the keyboard
  /// open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check.
  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
          return;
        }
        Navigator.of(context).pop();
      },
      child: FolkScaffold(
        title: "Association",
        body: ListView(
          padding: const EdgeInsets.all(FolkSpace.pagePadding),
          physics: const BouncingScrollPhysics(),
          children: [
            PrimaryButton(
              label: "Request Meeting with Guide",
              icon: Icons.event_available,
              onPressed: _openRequestSheet,
            ),
            const SizedBox(height: 26),
            Text("My Meetings",
                style: context.folkText.topBarTitle.copyWith(fontSize: 18)),
            const SizedBox(height: FolkSpace.md),
            _buildMeetings(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
