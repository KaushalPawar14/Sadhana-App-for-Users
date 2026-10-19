import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookCurrentBook.dart';
import '../utils/BookLibrary.dart';
import '../utils/BookSections.dart';
import '../utils/ReadingLanguages.dart';
import '../utils/SeenMarkers.dart';
import '../widgets/BookCardActions.dart';
import '../widgets/BookExtrasRow.dart';
import '../widgets/BookLevelSection.dart';
import '../widgets/CommitmentDateDialog.dart';
import '../widgets/CompletedBookTile.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkChip.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/LanguageButton.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/PrimaryButton.dart';
import 'BookReaderPage.dart';
import 'ComingSoonPage.dart';

/// Book library screen.
///
/// Firestore layout this screen relies on:
///   books/{level}            -> { book_1: "TITLE", ... }        (titles, read-only)
///   books/{level}_links      -> { book_1: "https://dropbox..." } (written by Guide App)
///   booksRead/{uid}_{level}_{bookKey} -> per-book progress for this student
///   users/{uid}.totalReadingSeconds   -> lifetime reading seconds
///   users/{uid}/dailyReading/{dd-MM-yyyy}.secondsToday -> today's reading seconds
class BooksSelectionScreen extends StatefulWidget {
  const BooksSelectionScreen(
      {super.key, this.library, this.uid, this.markCompleted});

  // Tests hand in their own data and student; the app never sets these.
  @visibleForTesting
  final BookLibrary? library;
  @visibleForTesting
  final String? uid;
  @visibleForTesting
  final Future<bool> Function({
    required String uid,
    required String level,
    required String bookKey,
    required String title,
    required String today,
  })? markCompleted;

  @override
  State<BooksSelectionScreen> createState() => _BooksSelectionScreenState();
}

class _BooksSelectionScreenState extends State<BooksSelectionScreen> {
  // Looked up when first used, so a screen built with test data never touches
  // Firebase.
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;
  FirebaseAuth get _auth => FirebaseAuth.instance;
  String? get _uid => widget.uid ?? _auth.currentUser?.uid;

  static const List<String> levels = ['level-1', 'level-2', 'level-3'];

  static const Map<String, String> levelTitles = {
    'level-1': 'Level 1',
    'level-2': 'Level 2',
    'level-3': 'Level 3',
  };

  /// Sibling document holding the Dropbox URLs for a level, for one reading
  /// [language]. English keeps the original, unsuffixed doc id — the real
  /// data that exists today (`level-1_links` etc.) is never migrated or
  /// renamed (Rule 3); every other language is an additional sibling
  /// document alongside it, following the exact convention already
  /// established for `{level}_links` itself. See the Rule 12 note at the
  /// admin-side write site (`BookLinkManager.dart`) for why this shape was
  /// chosen over restructuring `book_N` into a per-language map.
  static String linksDocId(String level, String language) =>
      language == 'en' ? '${level}_links' : '${level}_links_$language';

  /// Languages a student may choose as their standing reading language
  /// (Part 4). English is the only one with real content today; the others
  /// are wired end-to-end so an admin can add links later with no further
  /// client change — a book with no link in the chosen language falls back
  /// to the exact same "No link" / "Book link not available yet" treatment
  /// every book already gets when `{level}_links` has no entry for it, so a
  /// language with zero content today shows correctly rather than erroring.
  static const Map<String, String> kSupportedLanguages = kReadingLanguages;

  String? _userName;
  String? _role;
  String _language = 'en';

  /// The data behind the list. Both Firestore reads (the book titles and links,
  /// and this student's progress) are listened to at once, from the moment this
  /// screen opens, and shown as each arrives; the titles and links are also
  /// kept on the device so a later visit draws the list immediately. See
  /// `BookLibrary`.
  ///
  /// (Neither stream depends on `_language`; that only picks which links
  /// document a book's URL is read from, in memory.)
  late BookLibrary _library;

  BookLibrary _newLibrary() => BookLibrary(
        booksStream: _firestore.collection('books').snapshots().map((snap) => {
              for (final doc in snap.docs) doc.id: doc.data(),
            }),
        entriesStream: _firestore
            .collection('booksRead')
            .where('uid', isEqualTo: _uid ?? '')
            .snapshots()
            .map((snap) => [for (final doc in snap.docs) doc.data()]),
      );

  // Retry after a failed read: a fresh library listens to both streams again.
  void _retryLibrary() {
    if (widget.library != null) return;
    setState(() {
      _library.dispose();
      _library = _newLibrary();
    });
  }

  @override
  void initState() {
    super.initState();
    _library = widget.library ?? _newLibrary();
    if (widget.library == null) _loadUserMeta();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // guide-driven book commitments.
    final uid = _uid;
    if (widget.library == null && uid != null && uid.isNotEmpty) {
      SeenMarkers.markSeen(uid, 'bookCommitments');
    }
  }

  @override
  void dispose() {
    _library.dispose();
    super.dispose();
  }

  /// Name and role are needed to write the daily sadhana reading value, which
  /// lives in a name-keyed collection.
  Future<void> _loadUserMeta() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!mounted) return;
      final prefs = doc.data()?['readingPrefs'];
      final lang = prefs is Map ? prefs['language'] : null;
      setState(() {
        _userName = (doc.data()?['name'] ?? '').toString();
        _role = (doc.data()?['role'] ?? '').toString();
        if (lang is String && kSupportedLanguages.containsKey(lang)) {
          _language = lang;
        }
      });
    } catch (_) {
      // Non-fatal: the library still works, only the sadhana sync is skipped.
    }
  }

  /// Standing language choice (Part 4) — same nested map as reading
  /// prefs (font/theme), so a `set(..., merge:true)` here never disturbs
  /// those fields, and vice versa.
  Future<void> _setLanguage(String language) async {
    if (language == _language) return;
    setState(() => _language = language);

    final uid = _uid;
    if (uid == null) return;
    try {
      await _firestore.collection('users').doc(uid).set({
        'readingPrefs': {'language': language},
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal: the choice still applies for this session.
    }
  }

  /// `book_n` entries of a level document, numerically sorted. Keys that are
  /// not exactly `book_<digits>` are ignored so a stray field cannot crash this
  /// screen.
  List<MapEntry<String, String>> _sortedBooks(Map<String, dynamic>? data) {
    if (data == null) return [];

    final pattern = RegExp(r'^book_\d+$');

    final entries = data.entries
        .where((e) => pattern.hasMatch(e.key) && e.value is String)
        .map((e) => MapEntry(e.key, e.value as String))
        .toList();

    entries.sort((a, b) => int.parse(a.key.split('_')[1])
        .compareTo(int.parse(b.key.split('_')[1])));

    return entries;
  }

  String _todayKey() => DateFormat('dd-MM-yyyy').format(DateTime.now());

  // ---------------------------------------------------------------------------
  // Reading session tracking
  // ---------------------------------------------------------------------------

  /// Adds [seconds] to the lifetime total, to today's bucket, and mirrors
  /// today's minutes into today's sadhana report when one already exists.
  Future<void> _recordReadingSession(int seconds) async {
    final user = _auth.currentUser;
    if (user == null || seconds <= 0) return;

    final uid = user.uid;
    final today = _todayKey();

    try {
      // 1. Lifetime total on the user document.
      await _firestore.collection('users').doc(uid).set(
        {'totalReadingSeconds': FieldValue.increment(seconds)},
        SetOptions(merge: true),
      );

      final dailyRef = _firestore
          .collection('users')
          .doc(uid)
          .collection('dailyReading')
          .doc(today);

      // 2. Seconds banked before this session. Reading the bucket first lets
      //    us credit only the whole minutes this session newly completed, so
      //    leftover seconds are neither double-counted nor discarded.
      final beforeSnap = await dailyRef.get();
      final beforeRaw = beforeSnap.data()?['secondsToday'];
      final beforeSeconds = beforeRaw is num ? beforeRaw.toInt() : 0;

      // 3. Today's bucket.
      await dailyRef.set(
        {'secondsToday': FieldValue.increment(seconds)},
        SetOptions(merge: true),
      );

      // 4. Add the newly completed minutes to today's sadhana report.
      final minutesDelta =
          ((beforeSeconds + seconds) ~/ 60) - (beforeSeconds ~/ 60);

      if (minutesDelta > 0) {
        await _syncSadhanaReading(minutesDelta);
      }
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
        context,
        "Could not save reading time",
        Colors.red,
        Icons.error,
      );
    }
  }

  /// ADDS [minutesRead] to the reading field of today's existing sadhana
  /// report. Never overwrites a manually entered value, and never creates a
  /// report — if the student has not submitted today, nothing is written.
  Future<void> _syncSadhanaReading(int minutesRead) async {
    final name = _userName;
    if (name == null || name.isEmpty) return;

    // Localites (Master Task, 2026-09-03) behave exactly like Hostel here.
    final collectionName =
        (_role == 'Stay at Hostel' || _role == 'Stay at Localite')
            ? 'hostel-sadhana'
            : 'sadhana-reports';

    final docRef = _firestore
        .collection(collectionName)
        .doc(name)
        .collection('dates')
        .doc(_todayKey());

    final snap = await docRef.get();
    if (!snap.exists) return;

    await docRef.update({'bookReading': FieldValue.increment(minutesRead)});
  }

  // ---------------------------------------------------------------------------
  // Actions
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------
  // Commitment date (Part 5 — mandatory before reading begins)
  // ---------------------------------------------------------------------------

  /// Ensures a `commitmentDate` is on record before the reader opens.
  ///
  /// Triggers when `isCurrentBook` is not yet true — covering both a brand
  /// new book (no `booksRead` doc at all) and, per the product owner's
  /// explicit instruction to cover books already in progress, a book whose
  /// doc exists but was never asked for a commitment (retroactive case).
  ///
  /// A book that is already *finished* (`endDate` set) is exempt regardless
  /// of `isCurrentBook`/`commitmentDate` — reopening it to re-read or check
  /// notes must not re-trigger the mandatory dialog. This also means a
  /// finished book reopened this way can no longer have `isCurrentBook`
  /// silently resurrected to `true` by this gate's own write, which the
  /// unconditional version below it would otherwise have done.
  ///
  /// Returns false when the book must NOT go ahead: the student closed the
  /// dialog without choosing a date (Cancel, tap outside, back), the date could
  /// not be saved, or the widget was unmounted mid-flow. In the first case
  /// nothing at all has been written: the only write in this function is below
  /// `if (chosen == null || !mounted) return false;`, so a closed dialog never
  /// reaches it — the book is not started, not marked current, and the caller
  /// opens neither the reader nor the Update sheet.
  Future<bool> _ensureCommitmentDate({
    required String uid,
    required String level,
    required String bookKey,
    required String title,
  }) async {
    final docRef = _firestore
        .collection('booksRead')
        .doc('${uid}_${level}_$bookKey');

    Map<String, dynamic>? data;
    try {
      data = (await docRef.get()).data();
    } catch (_) {
      // A failed read must not silently skip the mandatory prompt — treat it
      // the same as "no doc yet".
      data = null;
    }

    // A completed book (end date, or marked finished by the student or the
    // guide) is exempt, and is never turned back into a current book here.
    if (isBookCompleted(data)) return true;

    final isCurrent = data?['isCurrentBook'] == true;
    final hasCommitment =
        (data?['commitmentDate'] as String?)?.trim().isNotEmpty == true;

    if (isCurrent && hasCommitment) return true;

    if (!mounted) return false;
    final chosen = await _showCommitmentDateDialog(title: title);
    if (chosen == null || !mounted) return false;

    try {
      // A transaction, so the doc is read again at the moment of writing: a
      // book that has been completed in the meantime (or whose first read
      // above failed) is never turned back into a current book. A failed
      // read fails the transaction too, which shows the message below.
      final stillOpen = await _firestore.runTransaction<bool>((tx) async {
        final latest = await tx.get(docRef);
        if (isBookCompleted(latest.data())) return false;
        tx.set(
            docRef,
            {
              'uid': uid,
              'level': level,
              'bookKey': bookKey,
              'bookTitle': title,
              'isCurrentBook': true,
              'commitmentDate': chosen,
              'commitmentSetAt': FieldValue.serverTimestamp(),
              'commitmentSetBy': 'student',
            },
            SetOptions(merge: true));
        return true;
      });
      if (!stillOpen) return true; // completed meanwhile: nothing to commit to
    } catch (_) {
      if (!mounted) return false;
      showSnackbar(
        context,
        "Could not save your commitment date — please try again",
        Colors.red,
        Icons.error,
      );
      return false;
    }

    return true;
  }

  /// The dialog itself is `showCommitmentDateDialog` (widgets/CommitmentDateDialog
  /// .dart): Cancel, a tap outside or the system back button close it and answer
  /// null, which [_ensureCommitmentDate] treats as "do nothing at all".
  Future<String?> _showCommitmentDateDialog({required String title}) =>
      showCommitmentDateDialog(context, title: title);

  /// Revert task (2026-08-30) — no sequential lock any more. A student may
  /// read any book, in any order, at any time; the product owner saw the
  /// hierarchy-lock system and decided against it. The only remaining gate
  /// before reading begins is [_ensureCommitmentDate].
  Future<void> _openBook({
    required String title,
    required String dropboxUrl,
    required String level,
    required String bookKey,
    // A book that is already current (it has its commitment date) opens at
    // once, with no questions.
    bool skipCommitmentGate = false,
  }) async {
    if (dropboxUrl.trim().isEmpty) {
      showSnackbar(
        context,
        "Book link not available yet",
        Colors.orange,
        Icons.link_off,
      );
      return;
    }

    final uid = _uid;
    if (uid == null) return;

    if (!skipCommitmentGate) {
      final committed = await _ensureCommitmentDate(
        uid: uid,
        level: level,
        bookKey: bookKey,
        title: title,
      );
      if (!committed || !mounted) return;
    }

    // The reader owns the timer — it starts only once the DOCX has been parsed
    // and text is on screen — and returns the elapsed seconds on pop. All
    // Firestore writes stay here so the totals are written exactly once.
    final elapsed = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderPage(
          dropboxUrl: dropboxUrl.trim(),
          bookTitle: title,
          bookKey: bookKey,
          level: level,
          uid: uid,
        ),
      ),
    );

    final seconds = elapsed is int ? elapsed : 0;

    await _recordReadingSession(seconds);

    if (!mounted || seconds <= 0) return;

    showSnackbar(
      context,
      "Reading time added: ${_formatDuration(seconds)}",
      Colors.green,
      Icons.timer,
    );
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return "${seconds}s";
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return s == 0 ? "${m}m" : "${m}m ${s}s";
  }

  /// Revert task (2026-08-30) — no lock re-check any more (see `_openBook`),
  /// and no cross-level advance (`orderedKeys`/`orderedTitles` params
  /// removed — nothing here needs a level's full ordered list once
  /// finishing no longer selects a next book).
  /// Part 2 item 1 — the commitment-date gate applies here too, not just
  /// to the in-app reader (`_openBook`). A student who taps "Update"
  /// directly on a book they've never opened in the reader must still set
  /// a commitment date before this sheet lets them record anything.
  Future<void> _openUpdateSheet({
    required String level,
    required String bookKey,
    required String title,
    required Map<String, dynamic>? entry,
  }) async {
    final user = _auth.currentUser;
    if (user == null) return;

    final committed = await _ensureCommitmentDate(
      uid: user.uid,
      level: level,
      bookKey: bookKey,
      title: title,
    );
    if (!committed || !mounted) return;

    // Re-read fresh rather than trusting the `entry` this function was
    // called with: `_ensureCommitmentDate` may just have CREATED the doc
    // (a book with no prior entry at all) or set `isCurrentBook: true` on
    // one that didn't have it — using the stale pre-gate `entry` here
    // would compute `wasCurrentBook` as false and let `save()` below
    // silently overwrite that write back to false.
    Map<String, dynamic>? freshEntry;
    try {
      freshEntry = (await _firestore
              .collection('booksRead')
              .doc('${user.uid}_${level}_$bookKey')
              .get())
          .data();
    } catch (_) {
      freshEntry = entry;
    }

    // `isCurrentBook` is not a student choice here — this holds only what
    // the system already has on record; the sheet below has no control
    // that can change it, and `save()` re-derives the final value itself
    // (`resolvedIsCurrentBook`) rather than trusting this local copy.
    final wasCurrentBook = isCurrentBookEntry(freshEntry);
    bool? madeNotes = freshEntry?['madeNotes'] is bool
        ? freshEntry!['madeNotes'] as bool
        : null;
    String? startDate = (freshEntry?['startDate'] as String?)?.trim();
    String? endDate = (freshEntry?['endDate'] as String?)?.trim();
    if (startDate != null && startDate.isEmpty) startDate = null;
    if (endDate != null && endDate.isEmpty) endDate = null;

    bool saving = false;

    // Captured here, read only after the sheet fully closes — the same
    // stale-context class of bug found and fixed on
    // `Pages/BoysDetails.dart`'s add-student dialog (Guide app) applied
    // here too: the previous version of this function's `save()` called
    // `showSnackbar(context, ...)` — the StatefulBuilder's OWN context —
    // immediately after `Navigator.pop(sheetContext)` popped the route that
    // owns it.
    bool saved = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickDate({required bool isStart}) async {
              final initial = DateTime.now();
              final picked = await showDatePicker(
                context: sheetContext,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked == null) return;
              final formatted = picked.toIso8601String().split('T')[0];
              setSheetState(() {
                if (isStart) {
                  startDate = formatted;
                } else {
                  endDate = formatted;
                }
              });
            }

            Future<void> save() async {
              if (madeNotes == null) {
                showSnackbar(
                  sheetContext,
                  "Please answer: have you made notes?",
                  Colors.red,
                  Icons.error,
                );
                return;
              }
              if (startDate == null) {
                showSnackbar(
                  sheetContext,
                  "Start date is required",
                  Colors.red,
                  Icons.error,
                );
                return;
              }

              setSheetState(() => saving = true);

              final isFinishingNow = endDate != null && endDate!.isNotEmpty;

              // The single source of truth for what `isCurrentBook`
              // becomes — never the raw student toggle (there is no
              // toggle any more — see this function's own header) and
              // never any other ad hoc check. A book with an `endDate` is
              // never current; this invariant survives the revert
              // unchanged.
              final resolvedCurrent = resolvedIsCurrentBook(
                requestedIsCurrentBook: wasCurrentBook,
                hasEndDate: isFinishingNow,
              );

              try {
                await _firestore
                    .collection('booksRead')
                    .doc('${user.uid}_${level}_$bookKey')
                    .set(
                  {
                    'isCurrentBook': resolvedCurrent,
                    'madeNotes': madeNotes,
                    'startDate': startDate,
                    'endDate': endDate,
                    'bookTitle': title,
                    'level': level,
                    'bookKey': bookKey,
                    'uid': user.uid,
                  },
                  SetOptions(merge: true),
                );

                saved = true;
                if (sheetContext.mounted) Navigator.pop(sheetContext);
              } catch (_) {
                setSheetState(() => saving = false);
                if (!sheetContext.mounted) return;
                showSnackbar(
                  sheetContext,
                  "Failed to save",
                  Colors.red,
                  Icons.error,
                );
              }
            }

            final colors = context.folk;
            final text = context.folkText;
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
                child: SingleChildScrollView(
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
                    Text(title, style: text.topBarTitle),
                    const SizedBox(height: 4),
                    Text(levelTitles[level] ?? level, style: text.caption),
                    const SizedBox(height: 20),

                    /// Auto-advance task, Part 1 items 1/2 — READ-ONLY.
                    /// Whether this is the current book is no longer a
                    /// student choice; the system decides via auto-advance,
                    /// so there is no toggle here any more, only a status
                    /// line reflecting whatever the system already set.
                    if (wasCurrentBook)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          gradient: FolkGradients.violet,
                          borderRadius:
                              BorderRadius.circular(FolkShape.tileRadius),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.menu_book,
                                size: 16, color: FolkColors.onGradient),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                "This is your current book",
                                style: text.onGradientSmall.copyWith(
                                    fontWeight: FontWeight.w700),
                              ),
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 16),

                    /// Made notes (mandatory)
                    Row(
                      children: [
                        Text("Have you made notes?", style: text.bodyStrong),
                        const SizedBox(width: 6),
                        Text("*",
                            style: text.bodyStrong
                                .copyWith(color: colors.calendarMissedText)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        FolkChip(
                          label: "Yes",
                          selected: madeNotes == true,
                          selectedStyle: FolkGradientStyle.green,
                          onTap: () => setSheetState(() => madeNotes = true),
                        ),
                        const SizedBox(width: 10),
                        FolkChip(
                          label: "No",
                          selected: madeNotes == false,
                          selectedStyle: FolkGradientStyle.coral,
                          onTap: () => setSheetState(() => madeNotes = false),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    /// Start date (mandatory)
                    _dateRow(
                      label: "Start date",
                      value: startDate,
                      required: true,
                      onTap: () => pickDate(isStart: true),
                    ),

                    const SizedBox(height: 10),

                    /// End date (optional)
                    _dateRow(
                      label: "End date",
                      value: endDate,
                      required: false,
                      onTap: () => pickDate(isStart: false),
                      onClear: endDate == null
                          ? null
                          : () => setSheetState(() => endDate = null),
                    ),

                    const SizedBox(height: 24),

                    PrimaryButton(
                      label: "Save",
                      loading: saving,
                      onPressed: saving ? null : save,
                    ),
                  ],
                ),
                ),
              ),
            );
          },
        );
      },
    );

    if (saved && mounted) {
      showSnackbar(
        context,
        "Book updated successfully",
        Colors.green,
        Icons.check_circle,
      );
    }
  }

  Widget _dateRow({
    required String label,
    required String? value,
    required bool required,
    required VoidCallback onTap,
    VoidCallback? onClear,
  }) {
    final colors = context.folk;
    final text = context.folkText;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        child: Container(
          constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: colors.surfaceSecondary,
            borderRadius: BorderRadius.circular(FolkShape.tileRadius),
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today, size: 18, color: colors.mutedText),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: Text(label, style: text.bodyStrong)),
                    if (required)
                      Text(" *",
                          style: text.bodyStrong
                              .copyWith(color: colors.calendarMissedText)),
                  ],
                ),
              ),
              Text(
                value ?? "Not set",
                style: value == null ? text.small : text.bodyStrong,
              ),
              if (onClear != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  color: colors.mutedText,
                  tooltip: 'Clear $label',
                  constraints: const BoxConstraints(
                      minWidth: FolkShape.touchTarget,
                      minHeight: FolkShape.touchTarget),
                  onPressed: onClear,
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  Widget _statusChip(Map<String, dynamic>? entry) {
    final colors = context.folk;
    final text = context.folkText;
    // Progress has not arrived yet: a ghost, never a wrong "Not Started".
    if (!_library.entriesLoaded) {
      return const GhostPlaceholder(
          width: 76, height: 22, radius: 11, showBars: false);
    }
    String label;
    LinearGradient? gradient;

    // Completed wins over any stored `isCurrentBook`: a finished book is never
    // shown as the current one.
    if (isBookCompleted(entry)) {
      label = "Completed";
      gradient = FolkGradients.green;
    } else if (isCurrentBookEntry(entry)) {
      label = "Current Book";
      gradient = FolkGradients.violet;
    } else {
      label = "Not Started";
      gradient = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? colors.surface : null,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        label,
        style: text.caption.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: gradient == null ? colors.mutedText : FolkColors.onGradient,
        ),
      ),
    );
  }

  Widget _levelBadge(String level) {
    final colors = context.folk;
    final text = context.folkText;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        levelTitles[level] ?? level,
        style: text.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }

  /// Part 2 items 2/3 — a commitment date cannot change until it has
  /// passed; once it has, the student may set ANY future date, uncapped
  /// (product owner's explicit decision — no one-week cap, unlike the
  /// removed extension system). Re-validated here as the actual
  /// authority, not merely relied upon via the button only appearing once
  /// the date has passed (Part 8 item 2 — enforced in code).
  Future<void> _changeCommitmentDateDialog({
    required String uid,
    required String level,
    required String bookKey,
    required String currentCommitmentDate,
  }) async {
    final today = DateTime.now().toIso8601String().split('T')[0];
    if (currentCommitmentDate.compareTo(today) >= 0) {
      showSnackbar(
        context,
        "You can change this once the current date has passed",
        Colors.orange,
        Icons.info,
      );
      return;
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      helpText: "New commitment date",
    );
    if (picked == null || !mounted) return;

    final proposed = picked.toIso8601String().split('T')[0];

    try {
      // Overwritten, not appended — the removed extension system's history
      // array is gone along with it; a commitment date is a single current
      // value, same as the original commitmentDate feature this builds on.
      await _firestore
          .collection('booksRead')
          .doc('${uid}_${level}_$bookKey')
          .set({
        'commitmentDate': proposed,
        'commitmentSetAt': FieldValue.serverTimestamp(),
        'commitmentSetBy': 'student',
      }, SetOptions(merge: true));

      if (!mounted) return;
      showSnackbar(context, "New commitment date saved", Colors.green,
          Icons.check_circle);
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not save the new date", Colors.red, Icons.error);
    }
  }

  /// "Mark as already completed" — for a book the student finished before (or
  /// outside) the app. Asks first; on confirm there is ONE write: `endDate` =
  /// today (the same `yyyy-MM-dd` every other end date uses) and
  /// `isCurrentBook: false` together, the same shape as the update sheet's
  /// completion write. It never overwrites an existing end date (a book that is
  /// already completed is left alone), and keeps an existing `startDate`.
  ///
  /// A book with no record yet gets one carrying the fields a normal start
  /// writes (`uid`, `level`, `bookKey`, `bookTitle`) plus `endDate`,
  /// `isCurrentBook: false` and `startDate` = today — exactly what the guide's
  /// "Mark finished" writes for a book that was never started. No reader of
  /// `booksRead` (Student app, Guide app, functions) needs a commitment date
  /// or a start date to treat a book as finished; they look at `endDate`.
  Future<void> _markAlreadyCompleted({
    required String level,
    required String bookKey,
    required String title,
  }) async {
    final uid = _uid;
    if (uid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return FolkDialog.alert(
          dialogContext,
          title: "Mark as completed",
          content: Text(
            "Mark '$title' as completed? Today's date will be saved as the end date.",
            style: text.small,
          ),
          actions: [
            TextButton(
              style: FolkDialog.quietButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              style: FolkDialog.primaryButton(colors, text),
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text("Mark completed"),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    final today = DateTime.now().toIso8601String().split('T')[0];
    final ref = _firestore.collection('booksRead').doc('${uid}_${level}_$bookKey');
    try {
      final written = widget.markCompleted != null
          ? await widget.markCompleted!(
              uid: uid, level: level, bookKey: bookKey, title: title, today: today)
          : await _firestore.runTransaction<bool>((tx) async {
              final latest = (await tx.get(ref)).data();
              // Never overwrites an existing end date (or a completion mark).
              final fields = alreadyCompletedFields(
                latest: latest,
                uid: uid,
                level: level,
                bookKey: bookKey,
                title: title,
                today: today,
              );
              if (fields == null) return false;
              tx.set(ref, fields, SetOptions(merge: true));
              return true;
            });
      if (!mounted) return;
      showSnackbar(
        context,
        written ? "Marked as completed" : "This book is already completed",
        written ? Colors.green : Colors.orange,
        written ? Icons.check_circle : Icons.info,
      );
    } catch (_) {
      if (!mounted) return;
      showSnackbar(
          context, "Could not mark this book as completed", Colors.red, Icons.error);
    }
  }

  /// Revert task (2026-08-30) — no `locked`/`blockingTitle`/`orderedKeys`/
  /// `orderedTitles` any more (no lock, no cross-level advance). Shows the
  /// student's own commitment date and who set it (Part 3 item 4 — a guide
  /// may set it too) whenever the book is current and unfinished, with a
  /// "Change date" action gated on the date having passed.
  Widget _bookCard({
    required String level,
    required String bookKey,
    required String title,
    required String url,
    required Map<String, dynamic>? entry,
    // Current books: tapping the title opens the reader, like Read.
    bool titleOpens = false,
  }) {
    final madeNotes = entry?['madeNotes'] == true;
    final hasEntry = entry != null;
    final startDate = (entry?['startDate'] as String?)?.trim();
    final isCurrent = isCurrentBookEntry(entry);
    final commitmentDate = (entry?['commitmentDate'] as String?)?.trim();
    final commitmentSetBy = (entry?['commitmentSetBy'] as String?)?.trim();
    // Master Task Part 2 item 3 — same convention as `commitmentSetBy`
    // above: the Guide app's `_confirmMarkBookFinished` now writes
    // `endedBy: 'guide'` alongside `endDate` in that one write, so a
    // student sees their guide ticked this rather than wondering why a
    // book they never marked finished themselves shows as completed.
    // Absent/anything else (including the student's own completion, which
    // never writes this field) shows the plain "Completed" chip/no note —
    // both read as "you did this," which is the correct default either way.
    final isFinished = isBookCompleted(entry);
    final endedBy = (entry?['endedBy'] as String?)?.trim();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final commitmentPassed =
        commitmentDate != null && commitmentDate.compareTo(today) < 0;
    final user = _auth.currentUser;

    final colors = context.folk;
    final text = context.folkText;

    return FolkCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      radius: FolkShape.tileRadius,
      color: colors.surfaceSecondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: FolkGradients.violet,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.menu_book,
                    size: 20, color: FolkColors.onGradient),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (titleOpens)
                      InkWell(
                        onTap: () => _openBook(
                          title: title,
                          dropboxUrl: url,
                          level: level,
                          bookKey: bookKey,
                          skipCommitmentGate:
                              (commitmentDate ?? '').isNotEmpty,
                        ),
                        borderRadius: BorderRadius.circular(8),
                        child: Text(title,
                            style: text.bodyStrong.copyWith(height: 1.3)),
                      )
                    else
                      Text(title, style: text.bodyStrong.copyWith(height: 1.3)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _levelBadge(level),
                        _statusChip(entry),
                      ],
                    ),
                  ],
                ),
              ),
              // Small and quiet: for a book the student has already finished.
              IconButton(
                tooltip: 'Mark as already completed',
                icon: Icon(Icons.task_alt, size: 20, color: colors.mutedText),
                constraints: const BoxConstraints(
                    minWidth: FolkShape.touchTarget,
                    minHeight: FolkShape.touchTarget),
                padding: EdgeInsets.zero,
                onPressed: () => _markAlreadyCompleted(
                  level: level,
                  bookKey: bookKey,
                  title: title,
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          /// Meta row: notes + start date
          Row(
            children: [
              Icon(
                hasEntry
                    ? (madeNotes ? Icons.check_circle : Icons.cancel)
                    : Icons.remove_circle_outline,
                size: 15,
                color: hasEntry
                    ? (madeNotes
                        ? FolkCalendarTokens.legendSubmitted
                        : FolkCalendarTokens.legendMissed)
                    : colors.mutedText,
              ),
              const SizedBox(width: 5),
              Text(
                hasEntry
                    ? (madeNotes ? "Notes made" : "No notes")
                    : "Notes not set",
                style: text.caption.copyWith(fontSize: 11),
              ),
              const SizedBox(width: 14),
              Icon(Icons.event, size: 15, color: colors.mutedText),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  startDate != null && startDate.isNotEmpty
                      ? "Started $startDate"
                      : "Not started",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.caption.copyWith(fontSize: 11),
                ),
              ),
            ],
          ),

          // Part 2/3 — the student's own commitment date, and who set it,
          // shown only while the book is current and unfinished.
          if (isCurrent && commitmentDate != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.flag,
                    size: 14,
                    color: commitmentPassed
                        ? colors.calendarMissedText
                        : colors.text),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    commitmentSetBy == 'guide'
                        ? "Committed to finish by $commitmentDate (set by guide)"
                        : "Committed to finish by $commitmentDate",
                    style: text.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: commitmentPassed
                            ? colors.calendarMissedText
                            : colors.text),
                  ),
                ),
                if (commitmentPassed && user != null)
                  TextButton(
                    onPressed: () => _changeCommitmentDateDialog(
                      uid: user.uid,
                      level: level,
                      bookKey: bookKey,
                      currentCommitmentDate: commitmentDate,
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(
                          FolkShape.touchTarget, FolkShape.touchTarget),
                      foregroundColor: colors.text,
                      textStyle: text.caption.copyWith(
                          fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    child: const Text("Change date"),
                  ),
              ],
            ),
          ],

          // Master Task Part 2 item 3 — mirrors the commitment row's own
          // "(set by guide)" convention above, for completion instead of
          // assignment.
          if (isFinished && endedBy == 'guide') ...[
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.check_circle,
                    size: 14, color: FolkCalendarTokens.legendSubmitted),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Marked complete by your guide",
                    style: text.caption.copyWith(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.text),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          BookCardActions(
            onRead: () => _openBook(
              title: title,
              dropboxUrl: url,
              level: level,
              bookKey: bookKey,
            ),
            onUpdate: () => _openUpdateSheet(
              level: level,
              bookKey: bookKey,
              title: title,
              entry: entry,
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingGhost() => const GhostScope(
        child: Padding(
          padding: EdgeInsets.all(FolkSpace.pagePadding),
          child: Column(
            children: [
              GhostPlaceholder(
                  width: double.infinity, height: 72, showBars: false),
              SizedBox(height: FolkSpace.cardGap),
              GhostPlaceholder(
                  width: double.infinity, height: 72, showBars: false),
              SizedBox(height: FolkSpace.cardGap),
              GhostPlaceholder(
                  width: double.infinity, height: 72, showBars: false),
            ],
          ),
        ),
      );

  /// Opens a book in the reader. A completed book is just opened (no
  /// commitment-date prompt); so is a current book that already has its date.
  void _openRow(BookRow row, BookDocs docs, {bool skipGate = false}) {
    final links = docs[linksDocId(row.level, _language)];
    _openBook(
      title: row.title,
      dropboxUrl: (links?[row.bookKey] ?? '').toString(),
      level: row.level,
      bookKey: row.bookKey,
      skipCommitmentGate: skipGate,
    );
  }

  Widget _fullCards(List<BookRow> rows, BookDocs docs,
      {bool titleOpens = false}) {
    return Column(
      children: [
        for (final r in rows)
          _bookCard(
            level: r.level,
            bookKey: r.bookKey,
            title: r.title,
            url: (docs[linksDocId(r.level, _language)]?[r.bookKey] ?? '')
                .toString(),
            entry: r.entry,
            titleOpens: titleOpens,
          ),
      ],
    );
  }

  String _countLabel(int n) => n == 1 ? '1 book' : '$n books';

  Widget _list(BookDocs docs) {
    final text = context.folkText;
    final entries = _library.entries;
    final loaded = entries != null;
    final sections = loaded
        ? classifyBooks(
            levels: levels,
            titlesByLevel: {
              for (final l in levels) l: _sortedBooks(docs[l]),
            },
            entries: entries,
          )
        : null;

    // Progress not read yet: a level section's body shows ghosts, never a
    // guess (a started book listed as "not started").
    Widget ghosts() => const GhostScope(
          child: Column(
            children: [
              GhostPlaceholder(
                  width: double.infinity, height: 72, showBars: false),
              SizedBox(height: FolkSpace.cardGap),
              GhostPlaceholder(
                  width: double.infinity, height: 72, showBars: false),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding,
          FolkSpace.xxl),
      physics: const BouncingScrollPhysics(),
      // Every child is keyed, so a section that is open stays open when the
      // others come and go. Each section starts CLOSED and builds nothing
      // until it is opened. A book is in exactly one of them.
      children: [
        if (sections != null && sections.current.isNotEmpty)
          BookLevelSection(
            key: const ValueKey('section-current'),
            title: 'Current books',
            subtitle: _countLabel(sections.current.length),
            bodyBuilder: (context) => _fullCards(sections.current, docs,
                titleOpens: true),
          ),
        for (final level in levels)
          BookLevelSection(
            key: ValueKey('section-$level'),
            title: levelTitles[level] ?? level,
            subtitle: sections == null
                ? null
                : _countLabel(sections.notStartedByLevel[level]!.length),
            bodyBuilder: (context) {
              if (sections == null) return ghosts();
              final rows = sections.notStartedByLevel[level]!;
              if (rows.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    sections.bookCountByLevel[level] == 0
                        ? "No books found for this level"
                        : "Every book in this level is current or completed",
                    style: text.body,
                  ),
                );
              }
              return _fullCards(rows, docs);
            },
          ),
        if (sections != null && sections.completed.isNotEmpty)
          BookLevelSection(
            key: const ValueKey('section-completed'),
            title: 'Completed books · ${sections.completed.length}',
            bodyBuilder: (context) => Column(
              children: [
                for (final r in sections.completed)
                  CompletedBookTile(
                    title: r.title,
                    onOpen: () => _openRow(r, docs, skipGate: true),
                  ),
              ],
            ),
          ),
        // Under the sections: "Notes" and "History" (their pages are to come).
        BookExtrasRow(
          key: const ValueKey('books-extras'),
          onNotes: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonPage(title: 'Notes', icon: Icons.sticky_note_2_outlined))),
          onHistory: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ComingSoonPage(title: 'History', icon: Icons.history_rounded))),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;

    return FolkScaffold(
      title: "My Books",
      onBack: () => Navigator.pop(context),
      // One compact language button in the top bar (EN -> हि -> ગુ -> తె).
      actions: [
        LanguageButton(language: _language, onChanged: _setLanguage),
      ],
      body: _uid == null
          ? Center(child: Text("Not signed in", style: text.body))
          : ListenableBuilder(
              listenable: _library,
              builder: (context, _) {
                final docs = _library.books;
                if (docs == null) {
                  if (_library.booksError != null) {
                    return FolkErrorRetry(
                      message: "Couldn't load the books just now.",
                      onRetry: _retryLibrary,
                    );
                  }
                  return _loadingGhost();
                }
                return _list(docs);
              },
            ),
    );
  }
}
