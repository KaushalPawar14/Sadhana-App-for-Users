/// The one rule every write path touching `booksRead.isCurrentBook` must
/// apply: a finished book (one with a real `endDate`) is never current.
///
/// ---------------------------------------------------------------------------
/// Revert task (2026-08-30) — replaces `utils/BookDeadlines.dart`
/// ---------------------------------------------------------------------------
/// The sequential-lock/automatic-deadline/auto-advance system the product
/// owner saw and decided against has been removed entirely — see
/// `BookPageList.dart`/`BookReaderPage.dart`'s own headers. Every other
/// function that used to live in `BookDeadlines.dart` (`isBookUnlockedAt`,
/// `blockingBookKeyFor`, `effectiveDeadlineFor`, `automaticDeadlineFor`,
/// `extensionsFor`, `isWithinExtensionCap`, `extensionCapDate`,
/// `hasUsedExtension`, `isPastDeadline`, `kLevelDeadlineDays`) went with it.
/// [resolvedIsCurrentBook] is the one invariant that survives the revert
/// unchanged — Part 2 item 4 of that task explicitly keeps it — so this
/// file was renamed rather than left as a "deadlines" file holding no
/// deadline logic at all.
library;

/// The one rule every write path in both apps must apply: a finished book
/// is never current, by definition. Callers pass the value the STUDENT (or
/// a guide assigning a book) would otherwise have written, and this clamps
/// it — a single source of truth for "what should `isCurrentBook` be,
/// given this book now has [hasEndDate]".
bool resolvedIsCurrentBook({
  required bool requestedIsCurrentBook,
  required bool hasEndDate,
}) {
  if (hasEndDate) return false;
  return requestedIsCurrentBook;
}

/// A book is COMPLETED when it has a real `endDate`, or was marked finished
/// by the student (`finishedViaButton`, written by the reader's Finish button)
/// or by the guide (`endedBy`, written with `endDate` by the Guide app's
/// "Mark finished"). Every one of those writes also sets `endDate`; the flags
/// are read as well so a half-written or hand-edited doc is still treated as
/// completed.
bool isBookCompleted(Map<String, dynamic>? entry) {
  if (entry == null) return false;
  final endDate = entry['endDate'];
  if (endDate != null && endDate.toString().trim().isNotEmpty) return true;
  if (entry['finishedViaButton'] == true) return true;
  final endedBy = entry['endedBy'];
  return endedBy != null && endedBy.toString().trim().isNotEmpty;
}

/// The only definition of "Current Book" any screen may use: flagged current
/// AND not completed. A completed book is never a current book, whatever the
/// stored `isCurrentBook` says.
bool isCurrentBookEntry(Map<String, dynamic>? entry) =>
    entry != null && entry['isCurrentBook'] == true && !isBookCompleted(entry);

/// The fields written when a student marks a book "already completed", or null
/// when nothing should be written because the book already is completed (an
/// existing end date is never overwritten).
///
/// One write: `endDate` = [today] and `isCurrentBook: false` together (the shape
/// of the update sheet's completion write), plus the identifying fields a book
/// record always carries. A record with no `startDate` gets today as its start
/// date — what the guide's "Mark finished" writes for a book never started; an
/// existing `startDate` is kept.
Map<String, Object?>? alreadyCompletedFields({
  required Map<String, dynamic>? latest,
  required String uid,
  required String level,
  required String bookKey,
  required String title,
  required String today,
}) {
  if (isBookCompleted(latest)) return null;
  final hasStart = (latest?['startDate'] as String?)?.trim().isNotEmpty == true;
  return {
    'uid': uid,
    'level': level,
    'bookKey': bookKey,
    'bookTitle': title,
    'endDate': today,
    'isCurrentBook': false,
    if (!hasStart) 'startDate': today,
  };
}
