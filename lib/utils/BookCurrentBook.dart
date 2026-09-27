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
