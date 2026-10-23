import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Master 2 B — what a student shares about a trip after it ends.
///
/// The server asks the morning after a trip's last day, and only the students
/// the guide marked Fully or Partially completed (`functions/
/// expeditionExperience.js`). It writes a stub into
/// `expeditionExperiences/{tripId}_{uid}`; the student fills in the answers
/// here. The rules let them change only the answers, only on their own
/// document, and only until `editableUntil` — seven days after the request.
///
/// It is written for the guides. The student sees it only while filling it in:
/// it is not shown on their profile, and once the window closes the app shows
/// nothing of it at all.

/// The three questions, in the order the student answers them. The Guide app
/// carries the same list, so what is asked and what the guide reads match.
const List<({String field, String question})> kExperienceQuestions = [
  (field: 'learned', question: 'What did you learn?'),
  (field: 'touched', question: 'What touched you most?'),
  (field: 'change', question: 'What will you change in your life?'),
];

/// The most any one answer may hold. The rules enforce the same number.
const int kExperienceMaxChars = 2000;

/// The server's request for this student, and whatever they have written.
class ExperienceRequest {
  final String id;
  final String tripId;
  final String tripName;
  final String status;
  final DateTime? editableUntil;
  final Map<String, String> answers;

  const ExperienceRequest({
    required this.id,
    required this.tripId,
    required this.tripName,
    required this.status,
    required this.editableUntil,
    required this.answers,
  });

  bool get submitted => status == 'submitted';

  /// Still inside the window the server set. After it, the student can neither
  /// edit nor see what they wrote.
  bool isOpen([DateTime? now]) {
    final until = editableUntil;
    return until != null && (now ?? DateTime.now()).isBefore(until);
  }

  String answer(String field) => answers[field] ?? '';

  /// "Open until 28 Oct" / "You can edit this until 28 Oct".
  String get untilLine {
    final until = editableUntil;
    if (until == null) return '';
    final day = DateFormat('dd MMM').format(until);
    return submitted ? 'You can edit this until $day' : 'Open until $day';
  }

  static ExperienceRequest? from(String id, Map<String, dynamic>? data) {
    if (data == null) return null;
    final tripId = (data['tripId'] ?? '').toString();
    if (tripId.isEmpty) return null;
    final until = data['editableUntil'];
    return ExperienceRequest(
      id: id,
      tripId: tripId,
      tripName: (data['tripName'] ?? '').toString().trim(),
      status: (data['status'] ?? 'requested').toString(),
      editableUntil: until is Timestamp ? until.toDate() : null,
      answers: {
        for (final f in const ['learned', 'touched', 'change', 'notes'])
          f: (data[f] ?? '').toString(),
      },
    );
  }
}

/// The requests this student can still act on, soonest to close first.
///
/// A request whose window has closed is dropped: the student may no longer
/// edit it, and it is not something to keep showing them.
List<ExperienceRequest> openRequests(
  Iterable<MapEntry<String, Map<String, dynamic>>> docs, {
  DateTime? now,
}) {
  final list = docs
      .map((e) => ExperienceRequest.from(e.key, e.value))
      .whereType<ExperienceRequest>()
      .where((r) => r.isOpen(now))
      .toList();
  list.sort((a, b) => a.editableUntil!.compareTo(b.editableUntil!));
  return list;
}

/// Whether anything was actually written. A form with every box empty is not
/// an experience, and saving it would only tell the guide nothing.
bool hasAnyAnswer(Map<String, String> answers) =>
    answers.values.any((v) => v.trim().isNotEmpty);
