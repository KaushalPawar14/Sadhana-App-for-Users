import 'BookHighlights.dart';

// Books -> Notes: the student's highlights, grouped by category and then by book.

/// One highlight as the Notes screens use it.
class NoteEntry {
  const NoteEntry({
    required this.id,
    required this.level,
    required this.bookKey,
    required this.bookTitle,
    required this.category,
    required this.text,
    required this.note,
    required this.chapter,
    required this.paragraph,
    required this.offset,
    required this.truncated,
  });

  final String id;
  final String level;
  final String bookKey;
  final String bookTitle;
  final HighlightCategory category;

  /// The highlighted text (the first 2000 characters of a very long one).
  final String text;
  final String note;

  /// Where it starts in the book: its place in reading order.
  final int chapter;
  final int paragraph;
  final int offset;
  final bool truncated;

  String get bookId => '${level}__$bookKey';
}

/// One book's highlights of one category, in reading order.
class NoteBook {
  const NoteBook({required this.bookId, required this.title, required this.entries});

  final String bookId;
  final String title;
  final List<NoteEntry> entries;
}

/// Reads stored `bookHighlights` documents (id + data). A damaged one is skipped.
List<NoteEntry> parseNotes(Iterable<({String id, Map<String, dynamic> data})> docs) {
  final out = <NoteEntry>[];
  int? i(Object? v) => v is num ? v.toInt() : null;
  for (final d in docs) {
    final data = d.data;
    final category = HighlightCategoryX.fromKey(data['category']);
    final chapter = i(data['chapterIndex']);
    final paragraph = i(data['startParagraph']);
    final offset = i(data['startOffset']);
    final text = (data['text'] ?? '').toString();
    if (category == null || chapter == null || paragraph == null || offset == null || text.trim().isEmpty) continue;
    final level = (data['level'] ?? '').toString();
    final bookKey = (data['bookKey'] ?? '').toString();
    final title = (data['bookTitle'] ?? '').toString().trim();
    out.add(NoteEntry(
      id: d.id,
      level: level,
      bookKey: bookKey,
      bookTitle: title.isEmpty ? 'Untitled book' : title,
      category: category,
      text: text,
      note: (data['note'] ?? '').toString().trim(),
      chapter: chapter,
      paragraph: paragraph,
      offset: offset,
      truncated: (i(data['textLength']) ?? text.length) > text.length,
    ));
  }
  return out;
}

int _readingOrder(NoteEntry a, NoteEntry b) {
  final c = a.chapter.compareTo(b.chapter);
  if (c != 0) return c;
  final p = a.paragraph.compareTo(b.paragraph);
  return p != 0 ? p : a.offset.compareTo(b.offset);
}

/// The books that have highlights in [category] (alphabetical by name), each with those highlights in reading order.
List<NoteBook> booksIn(HighlightCategory category, Iterable<NoteEntry> all) {
  final byBook = <String, List<NoteEntry>>{};
  for (final e in all) {
    if (e.category == category) (byBook[e.bookId] ??= []).add(e);
  }
  final books = [
    for (final entry in byBook.entries)
      NoteBook(
        bookId: entry.key,
        title: entry.value.first.bookTitle,
        entries: entry.value..sort(_readingOrder),
      ),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  return books;
}

/// How many highlights a category has.
int countIn(HighlightCategory category, Iterable<NoteEntry> all) => all.where((e) => e.category == category).length;

/// "3 of 12 · 25%" for the card at [index] (0-based) of [total].
String progressLabel(int index, int total) {
  if (total <= 0) return '';
  final n = (index + 1).clamp(1, total);
  return '$n of $total · ${(n * 100 / total).round()}%';
}

/// 0.0 - 1.0 for the progress bar.
double progressFraction(int index, int total) => total <= 0 ? 0 : ((index + 1).clamp(1, total)) / total;
