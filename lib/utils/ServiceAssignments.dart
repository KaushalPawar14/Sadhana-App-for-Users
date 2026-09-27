/// `serviceAssignments/{autoId}` — the Student app's own, DELIBERATELY
/// SMALLER copy of `Guides/.../utils/ServiceAssignments.dart`.
///
/// ---------------------------------------------------------------------------
/// Rule 14/15 — competence is guide-only BY CONSTRUCTION, confirmed here
/// ---------------------------------------------------------------------------
/// This is not a verbatim copy the way `ServiceBankContent.dart` is (that
/// content is identical for both apps by design). This file is the actual
/// enforcement mechanism for "a student can never set or change competence"
/// (Service Bank task, Part 5 item 3 / Part 7 item 2): there is NO
/// `setCompetence` function anywhere in this file, and no other function
/// here writes the `competence` field either. A student-app screen that
/// imports this file has no code path available to it that could write
/// `competence` — not a permission check that a modified client could
/// bypass, an absent capability. [ServiceCompetence] itself is READ-only
/// data (a student can see their own assessed competence — real
/// transparency, not a secret — they simply cannot produce or edit one).
///
/// The Guide app's copy additionally has `assignService`, `withdrawAssignment`
/// and `assignmentsForServiceStream` — none of those exist here either,
/// since a student never assigns, withdraws, or browses by-service across
/// other students.
///
/// Field shapes and status/competence constants are identical to the Guide
/// app's copy (so a doc written by either app is read identically by both) —
/// see that file for the full schema rationale.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

const String kStatusAssigned = 'assigned';
const String kStatusInProgress = 'inProgress';
const String kStatusCompleted = 'completed';
const String kStatusWithdrawn = 'withdrawn';

const List<String> kAssignmentStatuses = [
  kStatusAssigned,
  kStatusInProgress,
  kStatusCompleted,
];

const String kCompetenceNotYet = 'notYet';
const String kCompetenceYes = 'yes';

String statusLabel(String status) {
  switch (status) {
    case kStatusAssigned:
      return 'Assigned';
    case kStatusInProgress:
      return 'In progress';
    case kStatusCompleted:
      return 'Completed';
    case kStatusWithdrawn:
      return 'Withdrawn';
    default:
      return status;
  }
}

/// Read-only. A student can see a guide's assessment of them, never produce
/// or edit one — there is no constructor path here that writes this shape
/// back to Firestore.
class ServiceCompetence {
  final String level; // kCompetenceNotYet | kCompetenceYes
  final String assessedBy;
  final DateTime? assessedAt;
  final String? note;

  const ServiceCompetence({
    required this.level,
    required this.assessedBy,
    this.assessedAt,
    this.note,
  });

  factory ServiceCompetence.fromMap(Map<String, dynamic> map) {
    final ts = map['assessedAt'];
    return ServiceCompetence(
      level: (map['level'] ?? kCompetenceNotYet).toString(),
      assessedBy: (map['assessedBy'] ?? '').toString(),
      assessedAt: ts is Timestamp ? ts.toDate() : null,
      note: (map['note'] as String?)?.trim().isEmpty == true
          ? null
          : map['note'] as String?,
    );
  }
}

class ServiceAssignment {
  final String id;
  final int serviceNumber;
  final String studentUid;
  final String assignedByGuideId;
  final DateTime? assignedAt;
  final String status;
  final DateTime? statusUpdatedAt;
  final String statusUpdatedBy;
  final ServiceCompetence? competence;

  const ServiceAssignment({
    required this.id,
    required this.serviceNumber,
    required this.studentUid,
    required this.assignedByGuideId,
    this.assignedAt,
    required this.status,
    this.statusUpdatedAt,
    required this.statusUpdatedBy,
    this.competence,
  });

  factory ServiceAssignment.fromDoc(
    String id,
    Map<String, dynamic> data,
  ) {
    final assignedAtTs = data['assignedAt'];
    final statusUpdatedAtTs = data['statusUpdatedAt'];
    final competenceMap = data['competence'];

    return ServiceAssignment(
      id: id,
      serviceNumber: (data['serviceNumber'] as num?)?.toInt() ?? 0,
      studentUid: (data['studentUid'] ?? '').toString(),
      assignedByGuideId: (data['assignedByGuideId'] ?? '').toString(),
      assignedAt: assignedAtTs is Timestamp ? assignedAtTs.toDate() : null,
      status: (data['status'] ?? kStatusAssigned).toString(),
      statusUpdatedAt:
          statusUpdatedAtTs is Timestamp ? statusUpdatedAtTs.toDate() : null,
      statusUpdatedBy: (data['statusUpdatedBy'] ?? '').toString(),
      competence: competenceMap is Map<String, dynamic>
          ? ServiceCompetence.fromMap(competenceMap)
          : null,
    );
  }

  bool get isWithdrawn => status == kStatusWithdrawn;
}

CollectionReference<Map<String, dynamic>> _col() =>
    FirebaseFirestore.instance.collection('serviceAssignments');

/// The only query this app needs — a student only ever sees their OWN
/// assignments, never another student's or a by-service roster.
Stream<List<ServiceAssignment>> assignmentsForStudentStream(String studentUid) {
  return _col()
      .where('studentUid', isEqualTo: studentUid)
      .snapshots()
      .map((snap) => snap.docs
          .map((d) => ServiceAssignment.fromDoc(d.id, d.data()))
          .toList());
}

/// Part 5 item 3 — the ONLY write this file exposes. Updates `status` (and
/// its own stamp fields) only; the field mask below is exhaustive — there is
/// no way to pass a `competence` value through this function's signature at
/// all.
Future<void> updateAssignmentStatus({
  required String assignmentId,
  required String newStatus,
  required String updatedBy,
}) async {
  await _col().doc(assignmentId).set({
    'status': newStatus,
    'statusUpdatedAt': FieldValue.serverTimestamp(),
    'statusUpdatedBy': updatedBy,
  }, SetOptions(merge: true));
}
