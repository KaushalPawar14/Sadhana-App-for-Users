import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/SeenMarkers.dart';

/// Expeditions — pilgrimages and retreats.
///
/// Firestore:
///   expeditions/{id}                          -> trip details (Guide-written)
///   expeditionRegistrations/{tripId}_{uid}    -> this student's registration
///
/// The guide's FCM token lives at `adminUsers/{guideId}.fcmToken`.
class ExpeditionScreen extends StatefulWidget {
  final String uid;
  final String userName;
  final String role;

  const ExpeditionScreen({
    super.key,
    required this.uid,
    required this.userName,
    required this.role,
  });

  @override
  State<ExpeditionScreen> createState() => _ExpeditionScreenState();
}

class _ExpeditionScreenState extends State<ExpeditionScreen> {
  static const Color skyDark = Color(0xFF01579B);
  static const Color skyLight = Color(0xFF0288D1);

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  String _guideId = '';
  String _studentName = '';

  /// Trips whose description the student has expanded.
  final Set<String> _expanded = {};

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — both
  /// used to be constructed fresh directly in `build()` (the preceding
  /// comment there claimed "both streams are opened once here", which was
  /// only ever true in intent — `build()` re-runs this same code on every
  /// rebuild). Hoisted to fields, built once in `initState()` — safe
  /// unconditionally, since `widget.uid` is fixed for this screen's whole
  /// life (a pushed, single-student route).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _tripsStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _registrationsStream;

  @override
  void initState() {
    super.initState();
    _tripsStream = _firestore.collection('expeditions').snapshots();
    _registrationsStream = _firestore
        .collection('expeditionRegistrations')
        .where('studentUid', isEqualTo: widget.uid)
        .snapshots();
    _loadProfile();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // newly-posted trips.
    SeenMarkers.markSeen(widget.uid, 'expeditionTrips');
  }

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
      // Registration re-reads what it needs before writing.
    }
  }

  String _formatTs(dynamic value) {
    if (value is! Timestamp) return "Not set";
    return DateFormat('dd MMM yyyy').format(value.toDate());
  }

  static ({Color color, String label}) _statusStyle(String status) {
    switch (status) {
      case 'ongoing':
        return (color: Colors.orange, label: 'Ongoing');
      case 'completed':
        return (color: Colors.green, label: 'Completed');
      default:
        return (color: Colors.blue, label: 'Upcoming');
    }
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  Future<void> _register(String tripId, Map<String, dynamic> trip) async {
    final tripTitle = (trip['title'] ?? 'the trip').toString();

    try {
      await _firestore
          .collection('expeditionRegistrations')
          .doc('${tripId}_${widget.uid}')
          .set({
        'expeditionId': tripId,
        'studentUid': widget.uid,
        'studentName': _studentName,
        'registeredAt': FieldValue.serverTimestamp(),
        'hasReflected': false,
        'reflectionText': '',
        'reflectionSubmittedAt': null,
        'guideId': _guideId,
      });

      // The guide is notified server-side by
      // `functions/expeditionNotify.js`, reacting to this same write — no
      // client-side send any more (task: "Remove the embedded
      // service-account key from the Student app").

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Registered for $tripTitle")),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Could not register")),
      );
    }
  }

  Future<void> _openReflectionSheet(
    String regId,
    String tripTitle,
  ) async {
    String text = '';
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (text.trim().length < 50) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content:
                        Text("Please write at least 50 characters"),
                  ),
                );
                return;
              }

              setSheetState(() => saving = true);

              try {
                await _firestore
                    .collection('expeditionRegistrations')
                    .doc(regId)
                    .update({
                  'hasReflected': true,
                  'reflectionText': text.trim(),
                  'reflectionSubmittedAt': FieldValue.serverTimestamp(),
                });

                // The guide is notified server-side by
                // `functions/expeditionNotify.js`, reacting to this same
                // write — no client-side send any more (task: "Remove the
                // embedded service-account key from the Student app").

                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Reflection submitted")),
                );
              } catch (_) {
                setSheetState(() => saving = false);
                if (!sheetContext.mounted) return;
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text("Could not submit")),
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
                      "Write Reflection",
                      style:
                          TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tripTitle,
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      autofocus: true,
                      minLines: 3,
                      maxLines: 8,
                      onChanged: (v) => setSheetState(() => text = v),
                      decoration: InputDecoration(
                        hintText: "What did you experience?",
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${text.trim().length} / 50 characters minimum",
                      style: TextStyle(
                        fontSize: 11,
                        color: text.trim().length >= 50
                            ? Colors.green
                            : Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: skyDark,
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
                                "Submit",
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

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  Widget _shell({required Widget child}) {
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
      child: child,
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _upcomingCard(
    String tripId,
    Map<String, dynamic> trip,
    bool isRegistered,
    int registeredCount,
  ) {
    final description = (trip['description'] ?? '').toString();
    final isOpen = _expanded.contains(tripId);
    final max = trip['maxParticipants'];
    final capacity = max is num ? " / ${max.toInt()}" : "";

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (trip['title'] ?? 'Untitled').toString(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              if (isRegistered) _chip("Registered", Colors.green),
            ],
          ),
          const SizedBox(height: 6),
          _iconLine(Icons.place, (trip['location'] ?? 'No location').toString()),
          _iconLine(Icons.event, _formatTs(trip['tripDate'])),
          _iconLine(
            Icons.how_to_reg,
            "Register by ${_formatTs(trip['registrationDeadline'])}",
          ),
          _iconLine(Icons.people, "$registeredCount$capacity registered"),

          if (description.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              description,
              maxLines: isOpen ? null : 2,
              overflow: isOpen ? null : TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: Colors.grey.shade700,
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                if (isOpen) {
                  _expanded.remove(tripId);
                } else {
                  _expanded.add(tripId);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  isOpen ? "Show less" : "Read more",
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: skyDark,
                  ),
                ),
              ),
            ),
          ],

          const SizedBox(height: 12),

          if (!isRegistered)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _register(tripId, trip),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: skyDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  "Register",
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _myTripCard(
    String regId,
    Map<String, dynamic> reg,
    Map<String, dynamic>? trip,
  ) {
    final title = (trip?['title'] ?? 'Trip').toString();
    final status = (trip?['status'] ?? 'upcoming').toString();
    final style = _statusStyle(status);

    final hasReflected = reg['hasReflected'] == true;
    final reflectionText = (reg['reflectionText'] ?? '').toString();
    final canReflect = status == 'completed' && !hasReflected;

    return _shell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              _chip(style.label, style.color),
            ],
          ),
          const SizedBox(height: 6),
          if (trip != null) ...[
            _iconLine(
                Icons.place, (trip['location'] ?? 'No location').toString()),
            _iconLine(Icons.event, _formatTs(trip['tripDate'])),
          ],

          if (hasReflected) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                _chip("Reflection submitted", Colors.green),
              ],
            ),
            if (reflectionText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  reflectionText,
                  style: const TextStyle(fontSize: 12, height: 1.45),
                ),
              ),
            ],
          ],

          if (canReflect) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _openReflectionSheet(regId, title),
                icon: const Icon(Icons.edit_note, size: 18, color: Colors.white),
                label: const Text(
                  "Write Reflection",
                  style: TextStyle(color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  backgroundColor: skyDark,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeading(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: skyDark,
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(message, style: TextStyle(color: Colors.grey.shade600)),
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
          "Expeditions",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: skyDark,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [skyDark, skyLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      // Trips and this student's registrations drive both sections; both
      // streams are genuinely built once now, in initState() (see
      // `_tripsStream`/`_registrationsStream`'s own doc comment).
      body: StreamBuilder<QuerySnapshot>(
        stream: _tripsStream,
        builder: (context, tripSnap) {
          if (tripSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final tripDocs = tripSnap.data?.docs ?? [];
          final tripsById = <String, Map<String, dynamic>>{
            for (final d in tripDocs) d.id: d.data() as Map<String, dynamic>
          };

          return StreamBuilder<QuerySnapshot>(
            stream: _registrationsStream,
            builder: (context, regSnap) {
              final myRegs = regSnap.data?.docs ?? [];
              final myTripIds = <String>{
                for (final r in myRegs)
                  ((r.data() as Map<String, dynamic>)['expeditionId'] ?? '')
                      .toString()
              };

              // Upcoming trips, soonest first. Sorted client-side so no
              // composite index is needed alongside the status filter.
              final upcoming = tripDocs
                  .where((d) =>
                      ((d.data() as Map<String, dynamic>)['status'] ??
                          'upcoming') ==
                      'upcoming')
                  .toList()
                ..sort((a, b) {
                  final aDate = (a.data() as Map<String, dynamic>)['tripDate'];
                  final bDate = (b.data() as Map<String, dynamic>)['tripDate'];
                  if (aDate is! Timestamp || bDate is! Timestamp) return 0;
                  return aDate.compareTo(bDate);
                });

              return ListView(
                padding: const EdgeInsets.all(16),
                physics: const BouncingScrollPhysics(),
                children: [
                  _sectionHeading("Upcoming Trips"),
                  if (upcoming.isEmpty)
                    _emptyCard("No upcoming trips right now")
                  else
                    ...upcoming.map((doc) {
                      final trip = doc.data() as Map<String, dynamic>;

                      // Only this student's registrations are readable here,
                      // so the count reflects their own row plus nothing else
                      // unless the guide shares totals.
                      final count = myTripIds.contains(doc.id) ? 1 : 0;

                      return _upcomingCard(
                        doc.id,
                        trip,
                        myTripIds.contains(doc.id),
                        count,
                      );
                    }),

                  const SizedBox(height: 26),

                  _sectionHeading("My Trips"),
                  if (myRegs.isEmpty)
                    _emptyCard("You have not registered for any trips yet")
                  else
                    ...myRegs.map((reg) {
                      final data = reg.data() as Map<String, dynamic>;
                      final expId =
                          (data['expeditionId'] ?? '').toString();

                      return _myTripCard(reg.id, data, tripsById[expId]);
                    }),

                  const SizedBox(height: 20),
                ],
              );
            },
          );
        },
      ),
      ),
    );
  }
}
