import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/SeenMarkers.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';

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

  // Ongoing = saffron, completed = green, upcoming = violet.
  static ({FolkGradientStyle style, String label}) _statusStyle(String status) {
    switch (status) {
      case 'ongoing':
        return (style: FolkGradientStyle.saffron, label: 'Ongoing');
      case 'completed':
        return (style: FolkGradientStyle.green, label: 'Completed');
      default:
        return (style: FolkGradientStyle.violet, label: 'Upcoming');
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
            final colors = context.folk;
            final textStyles = context.folkText;
            Future<void> submit() async {
              if (text.trim().length < 50) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text("Please write at least 50 characters"),
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
                      "Write Reflection",
                      style: textStyles.topBarTitle.copyWith(fontSize: 18),
                    ),
                    const SizedBox(height: 4),
                    Text(tripTitle, style: textStyles.small),
                    const SizedBox(height: 18),
                    TextFormField(
                      autofocus: true,
                      minLines: 3,
                      maxLines: 8,
                      onChanged: (v) => setSheetState(() => text = v),
                      style: textStyles.body,
                      cursorColor: colors.text,
                      decoration: FolkDialog.field(context,
                              hint: "What did you experience?")
                          .copyWith(alignLabelWithHint: true),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "${text.trim().length} / 50 characters minimum",
                      style: textStyles.caption.copyWith(
                        fontSize: 11,
                        color: text.trim().length >= 50
                            ? FolkCalendarTokens.legendSubmitted
                            : colors.mutedText,
                      ),
                    ),
                    const SizedBox(height: 18),
                    PrimaryButton(
                      label: "Submit",
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

  // ---------------------------------------------------------------------------
  // Cards
  // ---------------------------------------------------------------------------

  Widget _shell({required Widget child}) {
    final colors = context.folk;
    return Container(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      padding: const EdgeInsets.all(FolkSpace.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        boxShadow: colors.cardShadows,
      ),
      child: child,
    );
  }

  Widget _chip(String label, FolkGradientStyle style) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: FolkGradients.of(style),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: context.folkText.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: FolkColors.onGradient,
        ),
      ),
    );
  }

  Widget _iconLine(IconData icon, String text) {
    final colors = context.folk;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.mutedText),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: context.folkText.small),
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
                  style: context.folkText.bodyStrong,
                ),
              ),
              if (isRegistered) _chip("Registered", FolkGradientStyle.green),
            ],
          ),
          const SizedBox(height: 6),
          _iconLine(
              Icons.place, (trip['location'] ?? 'No location').toString()),
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
              style:
                  context.folkText.small.copyWith(fontSize: 13.5, height: 1.45),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() {
                if (isOpen) {
                  _expanded.remove(tripId);
                } else {
                  _expanded.add(tripId);
                }
              }),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: FolkShape.touchTarget),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    isOpen ? "Show less" : "Read more",
                    style: context.folkText.bodyStrong.copyWith(fontSize: 13),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (!isRegistered)
            PrimaryButton(
              label: "Register",
              onPressed: () => _register(tripId, trip),
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
                  style: context.folkText.bodyStrong,
                ),
              ),
              _chip(style.label, style.style),
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
                _chip("Reflection submitted", FolkGradientStyle.green),
              ],
            ),
            if (reflectionText.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: context.folk.surfaceSecondary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  reflectionText,
                  style: context.folkText.body
                      .copyWith(fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ],
          if (canReflect) ...[
            const SizedBox(height: 12),
            PrimaryButton(
              label: "Write Reflection",
              icon: Icons.edit_note,
              onPressed: () => _openReflectionSheet(regId, title),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeading(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FolkSpace.md),
      child: Text(label,
          style: context.folkText.topBarTitle.copyWith(fontSize: 18)),
    );
  }

  Widget _emptyCard(String message) {
    final colors = context.folk;
    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        boxShadow: colors.cardShadows,
      ),
      child: Text(message, style: context.folkText.small),
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
        title: "Expeditions",
        // Trips and this student's registrations drive both sections; both
        // streams are genuinely built once now, in initState() (see
        // `_tripsStream`/`_registrationsStream`'s own doc comment).
        body: StreamBuilder<QuerySnapshot>(
          stream: _tripsStream,
          builder: (context, tripSnap) {
            if (tripSnap.connectionState == ConnectionState.waiting) {
              // Ghost trip cards while the trips load.
              return GhostScope(
                child: ListView(
                  physics: const NeverScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(FolkSpace.pagePadding),
                  children: [
                    for (var i = 0; i < 3; i++)
                      const Padding(
                        padding: EdgeInsets.only(bottom: FolkSpace.cardGap),
                        child: GhostPlaceholder(
                          width: double.infinity,
                          height: 180,
                          radius: FolkShape.tileRadius,
                        ),
                      ),
                  ],
                ),
              );
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
                    final aDate =
                        (a.data() as Map<String, dynamic>)['tripDate'];
                    final bDate =
                        (b.data() as Map<String, dynamic>)['tripDate'];
                    if (aDate is! Timestamp || bDate is! Timestamp) return 0;
                    return aDate.compareTo(bDate);
                  });

                return ListView(
                  padding: const EdgeInsets.all(FolkSpace.pagePadding),
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
                        final expId = (data['expeditionId'] ?? '').toString();

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
