import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/SeenMarkers.dart';

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
  static const Color saffronDark = Color(0xFFE65100);
  static const Color saffronLight = Color(0xFFFF8F00);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _guideId = '';
  String _studentName = '';

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) —
  /// `_buildMeetings()` used to construct this fresh every time it was
  /// called from `build()`. Hoisted to a field, built once in `initState()`
  /// — safe unconditionally: `widget.uid` is fixed for this screen's whole
  /// life (a pushed, single-student route; nothing ever rebuilds this
  /// widget with a different `uid`).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _meetingsStream;

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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Request a Meeting",
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "With $_guideId",
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
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
                      decoration: InputDecoration(
                        labelText: "Reason / Message (optional)",
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: saffronDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Submit Request",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              value,
              style: TextStyle(
                color: value == "Not set" ? Colors.grey.shade500 : Colors.black87,
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

  static ({Color color, String label}) _statusStyle(String status) {
    switch (status) {
      case 'confirmed':
        return (color: Colors.green, label: 'Confirmed');
      case 'cancelled':
        return (color: Colors.red, label: 'Cancelled');
      case 'completed':
        return (color: Colors.blue, label: 'Completed');
      default:
        return (color: Colors.orange, label: 'Pending');
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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: style.color.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: style.color.withOpacity(.4)),
                ),
                child: Text(
                  style.label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: style.color,
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
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
          if (guideId.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.person_outline,
                    size: 15, color: Colors.grey.shade600),
                const SizedBox(width: 5),
                Text(
                  guideId,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
              ],
            ),
          ],
          if (studentNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              "Your message: $studentNotes",
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
          if (guideNotes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                "Guide's notes: $guideNotes",
                style: const TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],

          /// Counter-proposal the student has already sent.
          if (isCounter) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.swap_horiz,
                          size: 14, color: Colors.purple),
                      const SizedBox(width: 5),
                      const Text(
                        "Counter-proposal sent",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ),
                  if (counterDate is Timestamp) ...[
                    const SizedBox(height: 4),
                    Text(
                      "You proposed: "
                      "${DateFormat('dd MMM yyyy, hh:mm a').format(counterDate.toDate())}",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                  if (counterNote.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      counterNote,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade700),
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
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Confirm Meeting",
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _openCounterProposalSheet(docId, data),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: saffronDark,
                      side: const BorderSide(color: saffronDark),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      "Propose New Time",
                      style: TextStyle(fontSize: 13),
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
                  const SnackBar(content: Text("Please choose a date and time")),
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Propose a New Time",
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),

                    TextFormField(
                      autofocus: true,
                      maxLines: 2,
                      onChanged: (v) => reason = v,
                      decoration: InputDecoration(
                        labelText: "Reason for change *",
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: saffronDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Send Proposal",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              "No meetings yet",
              style: TextStyle(color: Colors.grey.shade600),
            ),
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
      child: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          "Association",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: saffronDark,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [saffronDark, saffronLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _openRequestSheet,
              icon: const Icon(Icons.event_available, color: Colors.white),
              label: const Text(
                "Request Meeting with Guide",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: saffronDark,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
          const Text(
            "My Meetings",
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: saffronDark,
            ),
          ),
          const SizedBox(height: 12),
          _buildMeetings(),
          const SizedBox(height: 20),
        ],
      ),
      ),
    );
  }
}
