import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/FolkErrorRetry.dart';
import 'BookReaderPage.dart';

/// RDUA Modules — a structured study course of 50 fixed topics, each split
/// into two chapters, unconditionally visible to every student (no
/// level/category gating, unlike the books hierarchy — per product-owner
/// instruction).
///
/// Firestore layout:
///   rduaTopics/{topicId}   -> topicNumber, topicTitle,
///                             chapter1Title, chapter1FileRef,
///                             chapter2Title, chapter2FileRef
///   rduaProgress/{uid}_{topicId}_{chapterNum}
///                          -> uid, topicId, chapterNum, isRead, readAt
///
/// Rule 12 — why a new collection rather than folding into `books`: the
/// `books/{level}` hierarchy is intrinsically level-gated (a student's
/// visible books depend on `level-1`/`level-2`/`level-3`), while RDUA is
/// explicitly NOT gated by level or any other student attribute — forcing
/// it into `books` would mean either fabricating a fake "level" RDUA does
/// not have, or changing what `level` means for every existing book screen.
/// A fixed 2-chapter topic is also a different shape from a book (no
/// bookmark-across-many-chapters use case, no commitment-date flow) even
/// though it reuses the same DOCX reader. `rduaProgress` mirrors
/// `booksRead`'s per-student-per-content-unit precedent conceptually
/// (Rule 1) but stays deliberately simpler — no commitment date, no
/// notification system, per the product owner's own scoping of this task.
///
/// Reuses `BookReaderPage` entirely unmodified except for its `isRdua` flag
/// (added for this feature) — same DOCX parsing, chapter split, bookmarks,
/// font/theme prefs. Completion tracking is the one place that differs, and
/// `isRdua` is exactly what keeps it from ever touching `booksRead`.
class RduaScreen extends StatefulWidget {
  const RduaScreen({super.key});

  @override
  State<RduaScreen> createState() => _RduaScreenState();
}

class _RduaScreenState extends State<RduaScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// `{topicId}_{chapterNum}` -> isRead, kept live so a chapter just marked
  /// read reflects immediately without navigating away and back.
  Map<String, bool> _progress = {};

  /// Listener-leak fix (2026-09-09, size/perf task) — this subscription was
  /// never captured before, and this class had no `dispose()` override at
  /// all: the `if (!mounted) return;` guard inside the callback stopped a
  /// crash, but the underlying Firestore listener kept running (and
  /// billing reads) for as long as the process lived, not just this
  /// screen. Captured here so `dispose()` below can cancel it explicitly.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _progressSub;

  @override
  void initState() {
    super.initState();
    _subscribeProgress();
  }

  @override
  void dispose() {
    _progressSub?.cancel();
    super.dispose();
  }

  void _subscribeProgress() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    // Single equality filter — the shape every query in this project uses,
    // so no composite index is needed.
    _progressSub = _firestore
        .collection('rduaProgress')
        .where('uid', isEqualTo: uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      final next = <String, bool>{};
      for (final doc in snap.docs) {
        final data = doc.data();
        final topicId = (data['topicId'] ?? '').toString();
        final chapterNum = (data['chapterNum'] ?? '').toString();
        if (topicId.isEmpty || chapterNum.isEmpty) continue;
        next['${topicId}_$chapterNum'] = data['isRead'] == true;
      }
      setState(() => _progress = next);
    }, onError: (Object _) {
      // The ticks beside the chapters are a nicety: if they cannot be read the list still works.
    });
  }

  Future<void> _openChapter({
    required String topicId,
    required String chapterNum,
    required String chapterTitle,
    required String fileRef,
  }) async {
    if (fileRef.trim().isEmpty) return;
    final user = _auth.currentUser;
    if (user == null) return;

    // Elapsed reading seconds are intentionally discarded here — RDUA
    // chapters are not folded into `totalReadingSeconds`/`dailyReading`
    // (that metric line was never requested for this feature; only
    // completion tracking via `rduaProgress` was).
    await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => BookReaderPage(
          dropboxUrl: fileRef,
          bookTitle: chapterTitle,
          bookKey: chapterNum,
          level: topicId,
          uid: user.uid,
          isRdua: true,
        ),
      ),
    );
  }

  Widget _chapterRow({
    required String topicId,
    required String chapterNum,
    required String title,
    required String fileRef,
  }) {
    final colors = context.folk;
    final text = context.folkText;
    final isRead = _progress['${topicId}_$chapterNum'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
      onTap: () => _openChapter(
        topicId: topicId,
        chapterNum: chapterNum,
        chapterTitle: title,
        fileRef: fileRef,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          child: Row(
            children: [
              Icon(
                isRead ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 20,
                color: isRead
                    ? FolkCalendarTokens.legendSubmitted
                    : colors.disabledText,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: text.body.copyWith(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isRead ? colors.mutedText : colors.text,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, size: 18, color: colors.mutedText),
            ],
          ),
        ),
      ),
    );
  }

  Widget _topicTile(Map<String, dynamic> data) {
    final colors = context.folk;
    final text = context.folkText;
    final topicId = (data['topicNumber'] is num)
        ? (data['topicNumber'] as num).toInt().toString().padLeft(2, '0')
        : (data['id'] ?? '').toString();
    final topicTitle = (data['topicTitle'] ?? '').toString();
    final chapter1Title = (data['chapter1Title'] ?? '').toString();
    final chapter1FileRef = (data['chapter1FileRef'] ?? '').toString();
    final chapter2Title = (data['chapter2Title'] ?? '').toString();
    final chapter2FileRef = (data['chapter2FileRef'] ?? '').toString();

    final bothRead = (_progress['${topicId}_1'] == true) &&
        (_progress['${topicId}_2'] == true);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FolkShape.tileRadius),
          boxShadow: colors.cardShadows,
        ),
        // ExpansionTile paints its header/ink via the nearest Material
        // ancestor — without one here, the Container's own colour above sits
        // between it and the Scaffold's Material, triggering "ListTile
        // background color or ink splashes may be invisible" (recurred three
        // times in this project already — same fix each time).
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(FolkShape.tileRadius),
          clipBehavior: Clip.antiAlias,
          child: ExpansionTile(
            key: PageStorageKey(topicId),
            iconColor: colors.text,
            collapsedIconColor: colors.mutedText,
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Text(
              "$topicId. $topicTitle",
              style: text.bodyStrong,
            ),
            trailing: bothRead
                ? const Icon(Icons.check_circle,
                    color: FolkCalendarTokens.legendSubmitted, size: 22)
                : Icon(Icons.expand_more, color: colors.mutedText),
            children: [
              _chapterRow(
                topicId: topicId,
                chapterNum: '1',
                title: chapter1Title,
                fileRef: chapter1FileRef,
              ),
              Divider(height: 1, color: colors.surfaceSecondary),
              _chapterRow(
                topicId: topicId,
                chapterNum: '2',
                title: chapter2Title,
                fileRef: chapter2FileRef,
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: "RDUA Modules",
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore
            .collection('rduaTopics')
            .orderBy('topicNumber')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            // Ghost topic rows while the list loads.
            return GhostScope(
              child: ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(FolkSpace.pagePadding),
                children: [
                  for (var i = 0; i < 7; i++)
                    const Padding(
                      padding: EdgeInsets.only(bottom: FolkSpace.cardGap),
                      child: GhostPlaceholder(
                        width: double.infinity,
                        height: 56,
                        radius: FolkShape.tileRadius,
                        showBars: false,
                      ),
                    ),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            // The stream is built in `build`, so a rebuild reads it again.
            return FolkErrorRetry(
              message: "Couldn't load the topics just now.",
              onRetry: () => setState(() {}),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(
              child: Text("No modules available yet.", style: text.body),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(FolkSpace.pagePadding),
            physics: const BouncingScrollPhysics(),
            itemCount: docs.length,
            itemBuilder: (context, i) => EntryAnimation(
              key: ValueKey(docs[i].id),
              index: i,
              child: _topicTile(docs[i].data() as Map<String, dynamic>),
            ),
          );
        },
      ),
    );
  }
}
