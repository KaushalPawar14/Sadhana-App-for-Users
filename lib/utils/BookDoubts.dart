import 'package:cloud_firestore/cloud_firestore.dart';

/// A DOUBT raised while reading (the reader's fourth highlight category): the passage, the question, who it was sent to
/// (the AI or the student's guide) and the answer once it comes. Stored as `bookDoubts/{highlightId}` (see
/// `functions/doubts.js`); the student's own highlight (category "doubt") keeps the same id.
class Doubt {
  const Doubt({
    required this.id,
    required this.question,
    required this.mode,
    required this.status,
    this.askRound = 1,
    this.text = '',
    this.paragraph = '',
    this.bookTitle = '',
    this.answer,
    this.answeredBy,
    this.answeredByName,
  });

  final String id;
  final String question;

  /// "ai" or "guide": who the doubt was sent to (the latest ask).
  final String mode;

  /// "pending" or "answered".
  final String status;
  final int askRound;
  final String text;
  final String paragraph;
  final String bookTitle;
  final String? answer;

  /// "ai" or "guide".
  final String? answeredBy;
  final String? answeredByName;

  bool get answered => status == 'answered' && (answer ?? '').trim().isNotEmpty;
  bool get toGuide => mode == 'guide';

  /// Who answered, for the card: "AI assistant" or the guide's name.
  String get answeredByLabel {
    final n = (answeredByName ?? '').trim();
    if (n.isNotEmpty) return n;
    return answeredBy == 'guide' ? 'Your guide' : 'AI assistant';
  }

  static Doubt? fromFields(String id, Map<String, dynamic>? d) {
    if (d == null) return null;
    final question = (d['question'] ?? '').toString();
    if (question.trim().isEmpty) return null;
    final round = d['askRound'];
    return Doubt(
      id: id,
      question: question,
      mode: d['mode'] == 'guide' ? 'guide' : 'ai',
      status: d['status'] == 'answered' ? 'answered' : 'pending',
      askRound: round is num ? round.toInt() : 1,
      text: (d['text'] ?? '').toString(),
      paragraph: (d['paragraph'] ?? '').toString(),
      bookTitle: (d['bookTitle'] ?? '').toString(),
      answer: d['answer'] is String ? d['answer'] as String : null,
      answeredBy: d['answeredBy'] is String ? d['answeredBy'] as String : null,
      answeredByName: d['answeredByName'] is String ? d['answeredByName'] as String : null,
    );
  }
}

/// Where doubts are kept. The app uses [FirestoreDoubtStore]; tests hand in a fake.
abstract class DoubtStore {
  /// Creates the doubt of highlight [id] (pending, first ask).
  Future<void> create({
    required String id,
    required String uid,
    required String studentName,
    required String bookKey,
    required String level,
    required String bookTitle,
    required int chapterIndex,
    required String text,
    required String paragraph,
    required String question,
    required String mode,
  });

  Future<void> editQuestion(String id, String question);

  /// Asks again (the AI or the guide): back to pending with a higher round.
  Future<void> askAgain(String id, String mode);

  Future<void> delete(String id);

  /// Every doubt of this student (highlight id -> doubt).
  Future<Map<String, Doubt>> loadMine(String uid);

  /// One doubt, live (an answer arriving while the student looks at it).
  Stream<Doubt?> watch(String id);
}

class FirestoreDoubtStore implements DoubtStore {
  FirestoreDoubtStore([FirebaseFirestore? firestore]) : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _col => _db.collection('bookDoubts');

  static String _cut(String s, int n) => s.length <= n ? s : s.substring(0, n);

  @override
  Future<void> create({
    required String id,
    required String uid,
    required String studentName,
    required String bookKey,
    required String level,
    required String bookTitle,
    required int chapterIndex,
    required String text,
    required String paragraph,
    required String question,
    required String mode,
  }) =>
      _col.doc(id).set({
        'uid': uid,
        'studentName': studentName,
        'bookKey': bookKey,
        'level': level,
        'bookTitle': bookTitle,
        'chapterIndex': chapterIndex,
        'text': _cut(text, 2000),
        'paragraph': _cut(paragraph, 1500),
        'question': _cut(question.trim(), 1000),
        'mode': mode,
        'status': 'pending',
        'askRound': 1,
        'askedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> editQuestion(String id, String question) => _col.doc(id).update({'question': _cut(question.trim(), 1000)});

  @override
  Future<void> askAgain(String id, String mode) => _col.doc(id).update({
        'mode': mode,
        'status': 'pending',
        'askRound': FieldValue.increment(1),
        'askedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> delete(String id) => _col.doc(id).delete();

  @override
  Future<Map<String, Doubt>> loadMine(String uid) async {
    final snap = await _col.where('uid', isEqualTo: uid).get();
    return {
      for (final d in snap.docs)
        if (Doubt.fromFields(d.id, d.data()) case final doubt?) d.id: doubt,
    };
  }

  @override
  Stream<Doubt?> watch(String id) => _col.doc(id).snapshots().map((s) => Doubt.fromFields(s.id, s.data()));
}

/// The message the assistant is asked for a doubt: the question with the passage as its context.
String doubtMessageForAi({required String bookTitle, required String passage, required String question}) {
  final p = passage.trim().replaceAll(RegExp(r'\s+'), ' ');
  final cut = p.length > 700 ? '${p.substring(0, 700)}…' : p;
  final book = bookTitle.trim().isEmpty ? 'my reading' : '"${bookTitle.trim()}"';
  return 'I have a doubt about this passage from $book: “$cut”\n\nMy doubt: ${question.trim()}';
}

/// What the student is told when no questions are left today.
const String kDoubtNoQuestionsLeft = "You've used today's questions — you can ask tomorrow";
