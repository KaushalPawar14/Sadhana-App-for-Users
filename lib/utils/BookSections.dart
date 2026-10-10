import 'BookCurrentBook.dart';

// Which section of the Books screen each book belongs to. Every book lands in
// exactly ONE:
//
//   completed   isBookCompleted (an end date, or marked finished by the student
//               or the guide) — wins over everything, so a completed book is
//               never shown as current (invariant 5);
//   current     isCurrentBookEntry (flagged current and not completed);
//   notStarted  everything else: no record yet, or a record that is neither
//               current nor completed. These are listed under their level.
enum BookSection { current, notStarted, completed }

BookSection sectionOfEntry(Map<String, dynamic>? entry) {
  if (isBookCompleted(entry)) return BookSection.completed;
  if (isCurrentBookEntry(entry)) return BookSection.current;
  return BookSection.notStarted;
}

class BookRow {
  const BookRow({
    required this.level,
    required this.bookKey,
    required this.title,
    required this.entry,
    required this.section,
  });

  final String level;
  final String bookKey;
  final String title;

  // The student's `booksRead` record, or null when they have none.
  final Map<String, dynamic>? entry;
  final BookSection section;
}

class BookSections {
  const BookSections({
    required this.current,
    required this.completed,
    required this.notStartedByLevel,
    required this.bookCountByLevel,
  });

  final List<BookRow> current;
  final List<BookRow> completed;
  final Map<String, List<BookRow>> notStartedByLevel;

  // How many books each level has in all (to tell "no books" from "all started").
  final Map<String, int> bookCountByLevel;
}

int _number(String bookKey) => int.tryParse(bookKey.split('_').last) ?? 0;

int _byLevelThenNumber(BookRow a, BookRow b) {
  final l = a.level.compareTo(b.level);
  return l != 0 ? l : _number(a.bookKey).compareTo(_number(b.bookKey));
}

// [titlesByLevel]: level -> (bookKey -> title), the books each level offers.
// [entries]: this student's `booksRead` records.
BookSections classifyBooks({
  required List<String> levels,
  required Map<String, List<MapEntry<String, String>>> titlesByLevel,
  required List<Map<String, dynamic>> entries,
}) {
  final byId = <String, Map<String, dynamic>>{};
  for (final e in entries) {
    final level = (e['level'] ?? '').toString();
    final key = (e['bookKey'] ?? '').toString();
    if (level.isNotEmpty && key.isNotEmpty) byId['$level:$key'] = e;
  }

  final current = <BookRow>[];
  final completed = <BookRow>[];
  final notStarted = {for (final l in levels) l: <BookRow>[]};
  final counts = {for (final l in levels) l: 0};
  final seen = <String>{};

  void place(BookRow row) {
    switch (row.section) {
      case BookSection.current:
        current.add(row);
      case BookSection.completed:
        completed.add(row);
      case BookSection.notStarted:
        notStarted[row.level]?.add(row);
    }
  }

  // The books each level offers.
  for (final level in levels) {
    for (final b in titlesByLevel[level] ?? const <MapEntry<String, String>>[]) {
      final id = '$level:${b.key}';
      seen.add(id);
      counts[level] = counts[level]! + 1;
      final entry = byId[id];
      place(BookRow(
        level: level,
        bookKey: b.key,
        title: b.value,
        entry: entry,
        section: sectionOfEntry(entry),
      ));
    }
  }

  // Records for a book the level list no longer offers: still the student's
  // own current / completed book, so still shown (under its stored title).
  for (final entry in byId.entries) {
    if (seen.contains(entry.key)) continue;
    final data = entry.value;
    final section = sectionOfEntry(data);
    if (section == BookSection.notStarted) continue;
    final title = (data['bookTitle'] ?? '').toString().trim();
    if (title.isEmpty) continue;
    place(BookRow(
      level: (data['level'] ?? '').toString(),
      bookKey: (data['bookKey'] ?? '').toString(),
      title: title,
      entry: data,
      section: section,
    ));
  }

  current.sort(_byLevelThenNumber);
  completed.sort(_byLevelThenNumber);
  return BookSections(
    current: current,
    completed: completed,
    notStartedByLevel: notStarted,
    bookCountByLevel: counts,
  );
}
