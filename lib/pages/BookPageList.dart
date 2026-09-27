import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../utils/BookCurrentBook.dart';
import '../utils/ColorProvider.dart';
import '../utils/MalaLoading.dart';
import '../utils/SeenMarkers.dart';
import 'BookReaderPage.dart';

/// Book library screen.
///
/// Firestore layout this screen relies on:
///   books/{level}            -> { book_1: "TITLE", ... }        (titles, read-only)
///   books/{level}_links      -> { book_1: "https://dropbox..." } (written by Guide App)
///   booksRead/{uid}_{level}_{bookKey} -> per-book progress for this student
///   users/{uid}.totalReadingSeconds   -> lifetime reading seconds
///   users/{uid}/dailyReading/{dd-MM-yyyy}.secondsToday -> today's reading seconds
class BooksSelectionScreen extends StatefulWidget {
  const BooksSelectionScreen({super.key});

  @override
  State<BooksSelectionScreen> createState() => _BooksSelectionScreenState();
}

class _BooksSelectionScreenState extends State<BooksSelectionScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

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
  static const Map<String, String> kSupportedLanguages = {
    'en': 'English',
    'hi': 'हिन्दी',
    'gu': 'ગુજરાતી',
    'te': 'తెలుగు',
  };

  String? _userName;
  String? _role;
  String _language = 'en';

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — both
  /// used to be constructed fresh directly in `build()` on every rebuild
  /// (e.g. every `_setLanguage` call's `setState`, or a dark-mode toggle).
  /// Hoisted to fields, built once in `initState()`.
  ///
  /// Safe unconditionally: `_booksStream` has no filter to depend on at all,
  /// and `_booksReadStream`'s only filter is `user.uid`, fixed for this
  /// screen's whole life the same way as `ABCDEScreen.dart`'s own fields —
  /// neither stream depends on `_language` (that only picks which links
  /// document a one-off `.get()`-style read inside `build()` looks up, not
  /// either of these two live listeners).
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _booksStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _booksReadStream;

  @override
  void initState() {
    super.initState();
    _booksStream = _firestore.collection('books').snapshots();
    _booksReadStream = _firestore
        .collection('booksRead')
        .where('uid', isEqualTo: _auth.currentUser?.uid ?? '')
        .snapshots();
    _loadUserMeta();
    // Master Task 2026-09-10, Part 6 — opening this screen is "seen" for
    // guide-driven book commitments.
    final uid = _auth.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      SeenMarkers.markSeen(uid, 'bookCommitments');
    }
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

    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await _firestore.collection('users').doc(user.uid).set({
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
  /// Returns false only if leaving this function unable to proceed (widget
  /// unmounted mid-flow) — the dialog itself cannot be dismissed without a
  /// date, per the "not skippable" requirement.
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

    final isFinished = (data?['endDate'] as String?)?.trim().isNotEmpty == true;
    if (isFinished) return true;

    final isCurrent = data?['isCurrentBook'] == true;
    final hasCommitment =
        (data?['commitmentDate'] as String?)?.trim().isNotEmpty == true;

    if (isCurrent && hasCommitment) return true;

    if (!mounted) return false;
    final chosen = await _showCommitmentDateDialog(title: title);
    if (chosen == null || !mounted) return false;

    try {
      await docRef.set({
        'uid': uid,
        'level': level,
        'bookKey': bookKey,
        'bookTitle': title,
        'isCurrentBook': true,
        'commitmentDate': chosen,
        'commitmentSetAt': FieldValue.serverTimestamp(),
        'commitmentSetBy': 'student',
      }, SetOptions(merge: true));
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

  /// Non-dismissible: no cancel action, no barrier tap-to-close, and the
  /// system back gesture is blocked (`PopScope(canPop: false)`, the same
  /// idiom `BookReaderPage` already uses for its own exit confirmation) — a
  /// commitment date is mandatory before reading begins, per the product
  /// owner's explicit "not skippable" instruction.
  Future<String?> _showCommitmentDateDialog({required String title}) {
    DateTime? picked;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return PopScope<Object?>(
              canPop: false,
              child: AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text("Set your commitment date"),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Choose a target date to finish this book. This is "
                      "required before you can start reading.",
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () async {
                        final result = await showDatePicker(
                          context: dialogContext,
                          initialDate: picked ?? DateTime.now(),
                          firstDate: DateTime.now(),
                          lastDate: DateTime(2100),
                        );
                        if (result != null) {
                          setDialogState(() => picked = result);
                        }
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.calendar_today,
                                size: 18, color: Colors.grey.shade600),
                            const SizedBox(width: 12),
                            Text(
                              picked == null
                                  ? "Tap to choose a date"
                                  : picked!.toIso8601String().split('T')[0],
                              style: TextStyle(
                                color: picked == null
                                    ? Colors.grey.shade500
                                    : Colors.black87,
                                fontWeight: picked == null
                                    ? FontWeight.normal
                                    : FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    onPressed: picked == null
                        ? null
                        : () => Navigator.pop(
                              dialogContext,
                              picked!.toIso8601String().split('T')[0],
                            ),
                    child: const Text(
                      "Start Reading",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Revert task (2026-08-30) — no sequential lock any more. A student may
  /// read any book, in any order, at any time; the product owner saw the
  /// hierarchy-lock system and decided against it. The only remaining gate
  /// before reading begins is [_ensureCommitmentDate].
  Future<void> _openBook({
    required String title,
    required String dropboxUrl,
    required String level,
    required String bookKey,
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

    final user = _auth.currentUser;
    if (user == null) return;

    final committed = await _ensureCommitmentDate(
      uid: user.uid,
      level: level,
      bookKey: bookKey,
      title: title,
    );
    if (!committed || !mounted) return;

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
          uid: user.uid,
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
    final wasCurrentBook = freshEntry?['isCurrentBook'] == true;
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

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      levelTitles[level] ?? level,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
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
                          color: Colors.deepPurple.withOpacity(.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.menu_book,
                                size: 16, color: Colors.deepPurple),
                            SizedBox(width: 8),
                            Text(
                              "This is your current book",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Colors.deepPurple,
                                  fontSize: 13),
                            ),
                          ],
                        ),
                      ),

                    const Divider(height: 24),

                    /// Made notes (mandatory)
                    Row(
                      children: [
                        const Text(
                          "Have you made notes?",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        const Text("*", style: TextStyle(color: Colors.red)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ChoiceChip(
                          label: const Text("Yes"),
                          selected: madeNotes == true,
                          selectedColor: Colors.green.shade100,
                          onSelected: (_) =>
                              setSheetState(() => madeNotes = true),
                        ),
                        const SizedBox(width: 10),
                        ChoiceChip(
                          label: const Text("No"),
                          selected: madeNotes == false,
                          selectedColor: Colors.red.shade100,
                          onSelected: (_) =>
                              setSheetState(() => madeNotes = false),
                        ),
                      ],
                    ),

                    const Divider(height: 24),

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

                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton(
                        onPressed: saving ? null : save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Save",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                  ],
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (required)
                    const Text(" *", style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
            Text(
              value ?? "Not set",
              style: TextStyle(
                color: value == null ? Colors.grey.shade500 : Colors.black87,
                fontWeight: value == null ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            if (onClear != null)
              IconButton(
                icon: const Icon(Icons.close, size: 16),
                onPressed: onClear,
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Standing reading-language picker (Part 4). One chip row, chosen once —
  /// not per book — and applied to every level below by changing which
  /// `{level}_links` sibling document `_bookCard` reads its URL from.
  Widget _languageSelector(ColorProvider colorProvider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colorProvider.thirdColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Reading language",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kSupportedLanguages.entries.map((entry) {
              final selected = _language == entry.key;
              return ChoiceChip(
                label: Text(entry.value),
                selected: selected,
                onSelected: (_) => _setLanguage(entry.key),
                // Both states are fully opaque colours, not alpha-blended
                // against this container's own background — a translucent
                // `Colors.white24` chip (the prior bug) depends on exactly
                // what's visually behind it to land on a readable result,
                // and on a real device it didn't: white label text ended up
                // on a chip barely lighter than white itself.
                //
                // This container's own background is `colorProvider.thirdColor`,
                // which is `0xFF835DF1` in every branch of ColorProvider
                // (light init, dark init, and both toggle directions — see
                // ColorProvider.dart) — i.e. invariant to the app's light/dark
                // toggle, so a fix reasoned against this one fixed colour
                // holds in both of the app's theme states by construction.
                //
                // Selected: opaque white bg + deepPurple text — already high
                // contrast (deepPurple's luminance is low, white is maximal),
                // unchanged.
                // Unselected: an opaque, deliberately darker purple
                // (`#6647B8`, not a translucent overlay) + opaque white text.
                // White (luminance 1.0) against `#6647B8` (relative luminance
                // ≈0.108, computed via the WCAG formula) is a ≈6.6:1 contrast
                // ratio — comfortably past the 4.5:1 WCAG AA threshold for
                // normal-size text, and still visibly a "chip" against the
                // lighter `#835DF1` row behind it rather than blending in.
                selectedColor: Colors.white,
                backgroundColor: const Color(0xFF6647B8),
                labelStyle: TextStyle(
                  color: selected ? Colors.deepPurple : Colors.white,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(Map<String, dynamic>? entry) {
    String label;
    Color color;

    if (entry?['isCurrentBook'] == true) {
      label = "Current Book";
      color = Colors.blue;
    } else if ((entry?['endDate'] as String?)?.trim().isNotEmpty == true) {
      label = "Completed";
      color = Colors.green;
    } else {
      label = "Not Started";
      color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _levelBadge(String level) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withOpacity(.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        levelTitles[level] ?? level,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.deepPurple,
        ),
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
  }) {
    final madeNotes = entry?['madeNotes'] == true;
    final hasEntry = entry != null;
    final startDate = (entry?['startDate'] as String?)?.trim();
    final isCurrent = entry?['isCurrentBook'] == true &&
        !((entry?['endDate'] as String?)?.trim().isNotEmpty == true);
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
    final isFinished =
        (entry?['endDate'] as String?)?.trim().isNotEmpty == true;
    final endedBy = (entry?['endedBy'] as String?)?.trim();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final commitmentPassed =
        commitmentDate != null && commitmentDate.compareTo(today) < 0;
    final user = _auth.currentUser;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withOpacity(.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.menu_book,
                    size: 20, color: Colors.deepPurple),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
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
                    ? (madeNotes ? Colors.green : Colors.red)
                    : Colors.grey,
              ),
              const SizedBox(width: 5),
              Text(
                hasEntry
                    ? (madeNotes ? "Notes made" : "No notes")
                    : "Notes not set",
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
              ),
              const SizedBox(width: 14),
              Icon(Icons.event, size: 15, color: Colors.grey.shade600),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  startDate != null && startDate.isNotEmpty
                      ? "Started $startDate"
                      : "Not started",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
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
                    color:
                        commitmentPassed ? Colors.red : Colors.deepPurple),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    commitmentSetBy == 'guide'
                        ? "Committed to finish by $commitmentDate (set by guide)"
                        : "Committed to finish by $commitmentDate",
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color:
                            commitmentPassed ? Colors.red : Colors.deepPurple),
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
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    child: const Text("Change date",
                        style: TextStyle(fontSize: 11.5)),
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
                    size: 14, color: Colors.green),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "Marked complete by your guide",
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _openBook(
                    title: title,
                    dropboxUrl: url,
                    level: level,
                    bookKey: bookKey,
                  ),
                  icon: const Icon(Icons.chrome_reader_mode, size: 17),
                  label: const Text("Read"),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.deepPurple,
                    side: const BorderSide(color: Colors.deepPurple),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _openUpdateSheet(
                    level: level,
                    bookKey: bookKey,
                    title: title,
                    entry: entry,
                  ),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text("Update"),
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            title: Text(
              "My Books",
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: colorProvider.secondColor),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: user == null
              ? const Center(child: Text("Not signed in"))
              : StreamBuilder<QuerySnapshot>(
                  stream: _booksStream,
                  builder: (context, booksSnap) {
                    if (booksSnap.connectionState == ConnectionState.waiting) {
                      return const CustomLoader();
                    }

                    if (booksSnap.hasError) {
                      return Center(
                          child: Text("Error: ${booksSnap.error}"));
                    }

                    final Map<String, Map<String, dynamic>> bookDocs = {
                      for (var doc in booksSnap.data?.docs ?? [])
                        doc.id: (doc.data() as Map<String, dynamic>)
                    };

                    return StreamBuilder<QuerySnapshot>(
                      stream: _booksReadStream,
                      builder: (context, entriesSnap) {
                        // Entry lookup keyed by "{level}:{bookKey}".
                        final Map<String, Map<String, dynamic>> entries = {};
                        for (var doc in entriesSnap.data?.docs ?? []) {
                          final data = doc.data() as Map<String, dynamic>;
                          final lvl = (data['level'] ?? '').toString();
                          final key = (data['bookKey'] ?? '').toString();
                          if (lvl.isNotEmpty && key.isNotEmpty) {
                            entries['$lvl:$key'] = data;
                          }
                        }

                        return ListView(
                          padding: const EdgeInsets.all(16),
                          physics: const BouncingScrollPhysics(),
                          children: [
                            _languageSelector(colorProvider),
                            const SizedBox(height: 14),
                            ...levels.map((level) {
                            final books = _sortedBooks(bookDocs[level]);
                            final links =
                                bookDocs[linksDocId(level, _language)];

                            return Theme(
                              data: Theme.of(context)
                                  .copyWith(dividerColor: Colors.transparent),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 16),
                                // Colour lives on the Material below, not on a
                                // decoration, so the tile's ink and splash
                                // effects render against a real Material.
                                child: Material(
                                  color: colorProvider.thirdColor,
                                  borderRadius: BorderRadius.circular(20),
                                  clipBehavior: Clip.antiAlias,
                                  child: ExpansionTile(
                                  key: PageStorageKey(level),
                                  initiallyExpanded: level == 'level-1',
                                  tilePadding: const EdgeInsets.symmetric(
                                      horizontal: 18, vertical: 4),
                                  childrenPadding: const EdgeInsets.fromLTRB(
                                      14, 0, 14, 14),
                                  iconColor: Colors.white,
                                  collapsedIconColor: Colors.white,
                                  title: Text(
                                    levelTitles[level] ?? level,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  subtitle: Text(
                                    "${books.length} books",
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.white70,
                                    ),
                                  ),
                                  children: books.isEmpty
                                      ? [
                                          const Padding(
                                            padding: EdgeInsets.all(16),
                                            child: Text(
                                              "No books found for this level",
                                              style: TextStyle(
                                                  color: Colors.white),
                                            ),
                                          )
                                        ]
                                      : books.map((b) {
                                          // Revert task (2026-08-30) — no
                                          // hierarchy lock, so every book
                                          // renders identically regardless
                                          // of position; multiple books may
                                          // be current at once (Part 2 item
                                          // 4), so there is no single
                                          // level-level "Current: X" banner
                                          // any more — each card shows its
                                          // own status and commitment date.
                                          final entryData =
                                              entries['$level:${b.key}'];

                                          return _bookCard(
                                            level: level,
                                            bookKey: b.key,
                                            title: b.value,
                                            url: (links?[b.key] ?? '')
                                                .toString(),
                                            entry: entryData,
                                          );
                                        }).toList(),
                                  ),
                                ),
                              ),
                            );
                            }),
                          ],
                        );
                      },
                    );
                  },
                ),
        );
      },
    );
  }
}
