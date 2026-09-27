import 'package:flutter/material.dart';

import '../utils/SeenMarkers.dart';
import '../utils/ServiceAssignments.dart';
import '../utils/ServiceBankContent.dart';

/// Service Bank — replaces `pages/DevotionalServiceScreen.dart` entirely
/// (Service Bank task, Part 5). Reached from the same "D" tile on
/// `ABCDEScreen.dart` the old screen used, with the same constructor shape.
///
/// ---------------------------------------------------------------------------
/// Part 5 item 4 — shows ALL 19 services, not only the assigned ones
/// ---------------------------------------------------------------------------
/// Recommended and implemented: the content is a fixed, identical-for-
/// everyone curriculum (Part 2), so a student benefits from seeing the
/// whole roadmap ahead of them, not just what's currently assigned — the
/// same reasoning the old screen already applied to its 3 "Standard
/// Services" (shown to everyone regardless of assignment), just extended to
/// all 19 instead of 3. "Assigned to Me" stays the first, primary section
/// (with status controls); "All Services" below it is read-only reference
/// material for anything not currently assigned to this student.
///
/// ---------------------------------------------------------------------------
/// Part 5 item 3 / Rule 14/15 — competence is immune to any write here
/// ---------------------------------------------------------------------------
/// This file imports `utils/ServiceAssignments.dart` (this app's OWN copy —
/// see that file's header). That file has no `setCompetence` function at
/// all, so there is no code path anywhere in this screen that could write a
/// `competence` field — not a hidden check, an absent capability. The only
/// write anywhere below is [updateAssignmentStatus], and it never touches
/// `competence`.
class ServiceBankScreen extends StatefulWidget {
  final String uid;
  final String userName;
  final String role;

  const ServiceBankScreen({
    super.key,
    required this.uid,
    required this.userName,
    required this.role,
  });

  @override
  State<ServiceBankScreen> createState() => _ServiceBankScreenState();
}

class _ServiceBankScreenState extends State<ServiceBankScreen> {
  static const Color lotusDark = Color(0xFFB71C1C);
  static const Color lotusLight = Color(0xFFE53935);

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) —
  /// `assignmentsForStudentStream` (`utils/ServiceAssignments.dart`) used to
  /// be called fresh directly in `build()`, itself building a new
  /// `.where(...).snapshots()` query each time. Hoisted to a field, built
  /// once in `initState()` — safe unconditionally, since `widget.uid` is
  /// fixed for this screen's whole life (a pushed, single-student route).
  /// `ServiceAssignments.dart`'s own query (filters, scoping) is unchanged —
  /// only where it gets called from moved.
  late final Stream<List<ServiceAssignment>> _assignmentsStream;

  @override
  void initState() {
    super.initState();
    _assignmentsStream = assignmentsForStudentStream(widget.uid);
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // service assignments.
    SeenMarkers.markSeen(widget.uid, 'serviceAssignments');
  }

  Future<void> _advanceStatus(ServiceAssignment assignment) async {
    final order = [kStatusAssigned, kStatusInProgress, kStatusCompleted];
    final currentIndex = order.indexOf(assignment.status);
    if (currentIndex == -1 || currentIndex >= order.length - 1) return;

    await updateAssignmentStatus(
      assignmentId: assignment.id,
      newStatus: order[currentIndex + 1],
      updatedBy: widget.uid,
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case kStatusCompleted:
        return Colors.green;
      case kStatusInProgress:
        return Colors.orange;
      default:
        return Colors.blueGrey;
    }
  }

  Widget _statusChip(ServiceAssignment assignment) {
    final isCompleted = assignment.status == kStatusCompleted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _statusColor(assignment.status).withOpacity(.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            statusLabel(assignment.status),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _statusColor(assignment.status)),
          ),
          if (!isCompleted) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: () => _advanceStatus(assignment),
              child: Icon(Icons.arrow_forward,
                  size: 13, color: _statusColor(assignment.status)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _competenceRow(ServiceCompetence competence) {
    final isYes = competence.level == kCompetenceYes;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(isYes ? Icons.check_circle : Icons.hourglass_bottom,
              size: 14, color: isYes ? Colors.green : Colors.grey.shade500),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              // Read-only display of the guide's own assessment — see this
              // file's header for why nothing here can ever write this.
              "Guide assessment: ${isYes ? 'Yes' : 'Not yet'}"
              "${competence.note != null ? ' — ${competence.note}' : ''}",
              style: TextStyle(
                  fontSize: 11.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _serviceExpansionTile(ServiceBankEntry service,
      {ServiceAssignment? assignment}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 8,
              offset: const Offset(0, 4)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      // ExpansionTile paints its header/ink via the nearest Material
      // ancestor — without one here, the Container's own `color: white`
      // above sits between it and the Scaffold's Material, triggering
      // "ListTile background color or ink splashes may be invisible" (this
      // exact warning has recurred three times in this project already —
      // same fix each time).
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            leading: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                  shape: BoxShape.circle, color: lotusLight.withOpacity(.1)),
              child: Center(
                child: Text("${service.number}",
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, color: lotusDark)),
              ),
            ),
            title: Text(service.title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14, height: 1.3)),
            subtitle: assignment == null
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [_statusChip(assignment)]),
                  ),
            children: [
              if (assignment != null && assignment.competence != null)
                _competenceRow(assignment.competence!),
              const SizedBox(height: 8),
              ...service.subPoints.map((p) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("•  ",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Expanded(
                            child: Text(p,
                                style: const TextStyle(
                                    fontSize: 13, height: 1.35))),
                      ],
                    ),
                  )),
              if (service.nuance != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Text(service.nuance!,
                      style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.amber.shade900,
                          height: 1.4)),
                ),
              ],
              if (service.context != null) ...[
                const SizedBox(height: 6),
                Text(service.context!,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey.shade600,
                        height: 1.4)),
              ],
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: lotusDark.withOpacity(.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                  "Assessment question: “${service.assessmentQuestion}”",
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: lotusDark,
                      height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionHeading(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(label,
          style: const TextStyle(
              fontSize: 17, fontWeight: FontWeight.bold, color: lotusDark)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        elevation: 0,
        title: const Text("Service Bank",
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: lotusDark,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [lotusDark, lotusLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
          ),
        ),
      ),
      body: StreamBuilder<List<ServiceAssignment>>(
        stream: _assignmentsStream,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final active = snap.data!.where((a) => !a.isWithdrawn).toList()
            ..sort((a, b) => a.serviceNumber.compareTo(b.serviceNumber));
          final assignedNumbers = active.map((a) => a.serviceNumber).toSet();

          return ListView(
            padding: const EdgeInsets.all(16),
            physics: const BouncingScrollPhysics(),
            children: [
              _sectionHeading("Assigned to Me"),
              if (active.isEmpty)
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16)),
                  child: Text("No services assigned yet",
                      style: TextStyle(color: Colors.grey.shade600)),
                )
              else
                ...active.map((a) {
                  final service = kServiceBank.firstWhere(
                      (s) => s.number == a.serviceNumber,
                      orElse: () => kServiceBank.first);
                  return _serviceExpansionTile(service, assignment: a);
                }),
              const SizedBox(height: 26),
              _sectionHeading("All Services"),
              ...kServiceBank
                  .where((s) => !assignedNumbers.contains(s.number))
                  .map((s) => _serviceExpansionTile(s)),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}
