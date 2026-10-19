import 'package:cloud_firestore/cloud_firestore.dart';

import 'BookHighlights.dart';

/// Where a student's book highlights are kept.
///
/// ---------------------------------------------------------------------------
/// Why a NEW collection (Rule 12)
/// ---------------------------------------------------------------------------
/// `bookHighlights/{id}`: one small document per highlight. Nothing existing can hold it: `bookmarks` is ONE
/// document per student and book (a single paragraph position, overwritten), `booksRead` is the book's progress
/// record, and `users` is one document per student - a student can make hundreds of highlights, each with a note
/// of any length, so they cannot live in a field of any of those (a document is capped at 1 MB and every read
/// would drag them all in). It is PRIVATE to the student: the rules let only the owner read, list, write or
/// delete (no admin branch at all - guides cannot read them), and the student-deletion cascade removes them.
///
/// The document: uid, bookKey, level, bookTitle, chapterIndex, startParagraph, startOffset, endParagraph,
/// endOffset, text (up to 2000 characters), textLength, snippetStart, snippetEnd, category
/// ('good' | 'excellent' | 'rare'), note, createdAt, updatedAt.
abstract class HighlightStore {
  /// Every highlight of this student in this book.
  Future<List<BookHighlight>> load({required String uid, required String bookKey, required String level});

  /// Saves a new highlight; returns it with its id.
  Future<BookHighlight> add({
    required String uid,
    required String bookKey,
    required String level,
    required String bookTitle,
    required BookHighlight highlight,
  });

  /// Changes some of a highlight's fields (anchor, category, note ...).
  Future<void> update(String id, Map<String, Object?> fields);

  Future<void> delete(String id);
}

class FirestoreHighlightStore implements HighlightStore {
  FirestoreHighlightStore([this._db]);

  final FirebaseFirestore? _db;

  FirebaseFirestore get db => _db ?? FirebaseFirestore.instance;
  CollectionReference<Map<String, dynamic>> get _col => db.collection('bookHighlights');

  @override
  Future<List<BookHighlight>> load({required String uid, required String bookKey, required String level}) async {
    final snap = await _col
        .where('uid', isEqualTo: uid)
        .where('bookKey', isEqualTo: bookKey)
        .where('level', isEqualTo: level)
        .get();
    final out = <BookHighlight>[];
    for (final d in snap.docs) {
      final created = d.data()['createdAt'];
      final h = BookHighlight.fromFields(d.id, d.data(), createdMillis: created is Timestamp ? created.millisecondsSinceEpoch : 0);
      if (h != null) out.add(h);
    }
    out.sort((a, b) => a.createdMillis.compareTo(b.createdMillis));
    return out;
  }

  @override
  Future<BookHighlight> add({
    required String uid,
    required String bookKey,
    required String level,
    required String bookTitle,
    required BookHighlight highlight,
  }) async {
    final ref = _col.doc();
    await ref.set({
      'uid': uid,
      'bookKey': bookKey,
      'level': level,
      'bookTitle': bookTitle,
      ...highlight.toFields(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return BookHighlight(
      id: ref.id,
      anchor: highlight.anchor,
      text: highlight.text,
      textLength: highlight.textLength,
      snippetStart: highlight.snippetStart,
      snippetEnd: highlight.snippetEnd,
      category: highlight.category,
      note: highlight.note,
      createdMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  Future<void> update(String id, Map<String, Object?> fields) =>
      _col.doc(id).update({...fields, 'updatedAt': FieldValue.serverTimestamp()});

  @override
  Future<void> delete(String id) => _col.doc(id).delete();
}
