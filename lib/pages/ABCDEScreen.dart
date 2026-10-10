import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/DailyMessageService.dart';
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/BookCurrentBook.dart';
import '../utils/UnseenFeatureBadge.dart';
import '../widgets/DailyMessageCard.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FloatingPillNavBar.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/GhostedTextLine.dart';
import '../widgets/CountUpText.dart';
import '../widgets/JourneyMosaic.dart';
import '../widgets/SectionDivider.dart';
import 'AssistantScreen.dart' show AssistantScreen, kAssistantRouteName;
import 'AssociationScreen.dart';
import 'BookPageList.dart';
import 'ChantingScreen.dart';
import 'ServiceBankScreen.dart';
import 'ExpeditionScreen.dart';
import 'Phase7Placeholders.dart';

/// The ABCDE journey home screen.
///
/// Five tall cards, one per limb of practice. Progress lines are read live
/// from Firestore where data exists; A/D/E currently have no backing data.
class ABCDEScreen extends StatefulWidget {
  const ABCDEScreen({super.key});

  @override
  State<ABCDEScreen> createState() => _ABCDEScreenState();
}

class _ABCDEScreenState extends State<ABCDEScreen> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Sadhana reports are keyed by the student's name, not their uid, and the
  /// collection differs by role — both are needed for the chanting card.
  String? _userName;
  String? _role;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — these
  /// three used to be constructed fresh inside `_associationProgress`/
  /// `_booksProgress`/`_chantingProgress`, called directly from `build()`,
  /// so every rebuild of this screen (any `setState` here, or an ancestor
  /// like `Consumer<ColorProvider>` on a dark-mode toggle) tore down and
  /// re-created all three Firestore listeners. Hoisted to fields, built
  /// once in `initState()`, exactly the pattern this codebase already uses
  /// correctly in `ChantingScreen.dart`/`Calendar.dart`.
  ///
  /// Safe to build unconditionally here (no "rebuild when X changes"
  /// handling needed, unlike a stream keyed to a selectable value): `uid`
  /// comes from `_auth.currentUser`, which cannot change for the lifetime
  /// of this already-signed-in screen without the whole widget tree being
  /// torn down and recreated first (a real account switch requires signing
  /// out, which unmounts this screen entirely).
  late final String _uid;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _associationStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _booksStream;
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _userDocStream;

  @override
  void initState() {
    super.initState();
    _uid = _auth.currentUser?.uid ?? '';
    _associationStream = _firestore
        .collection('associations')
        .where('studentUid', isEqualTo: _uid)
        .snapshots();
    _booksStream = _firestore
        .collection('booksRead')
        .where('uid', isEqualTo: _uid)
        .snapshots();
    _userDocStream = _firestore.collection('users').doc(_uid).snapshots();
    _loadUserMeta();
  }

  /// Opens Ask by the same route name the floating button uses, so the
  /// button hides there. Today's message itself comes from
  /// `DailyMessageService` (started when the app opened); this screen only
  /// shows it, so nothing needs re-reading when Ask closes.
  Future<void> _openAssistant() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        settings: const RouteSettings(name: kAssistantRouteName),
        builder: (_) => AssistantScreen(uid: _uid),
      ),
    );
  }

  /// The first word of the name this screen already loads (`_loadUserMeta`),
  /// for the greeting. Null until it has loaded.
  String? _firstName() {
    final name = _userName;
    if (name == null) return null;
    final trimmed = name.trim();
    return trimmed.isEmpty ? '' : trimmed.split(RegExp(r'\s+')).first;
  }

  Future<void> _loadUserMeta() async {
    final user = _auth.currentUser;
    if (user == null) return;

    try {
      final doc = await _firestore.collection('users').doc(user.uid).get();
      if (!mounted) return;
      setState(() {
        _userName = (doc.data()?['name'] ?? '').toString();
        _role = (doc.data()?['role'] ?? '').toString();
      });
    } catch (_) {
      // Non-fatal — the chanting card simply falls back to its empty state.
    }
  }

  // ---------------------------------------------------------------------------
  // Live progress lines
  // ---------------------------------------------------------------------------

  /// A — Association. Reads the real `associations` collection, filtered on
  /// `studentUid` to match how both apps write the document. Returns live data
  /// once the student has meetings.
  ///
  /// Known limitation: every meeting the student has ever had is counted,
  /// whatever its status or date — nothing filters by month, and a cancelled
  /// meeting from months ago still adds to the total. The label still says
  /// "sessions this month". Open item; deliberately not fixed here.
  Widget _associationProgress() {
    return StreamBuilder<QuerySnapshot>(
      stream: _associationStream,
      builder: (context, snapshot) => _ghostedProgress(snapshot, () {
        final count = snapshot.data?.docs.length ?? 0;
        return _progressText(
          count > 0 ? "$count sessions this month" : "No sessions yet",
        );
      }),
    );
  }

  /// B — Books. Filters on uid only; `isCurrentBook` is matched client-side so
  /// no composite index is required.
  Widget _booksProgress() {
    return StreamBuilder<QuerySnapshot>(
      stream: _booksStream,
      builder: (context, snapshot) => _ghostedProgress(snapshot, () {
        final docs = snapshot.data?.docs ?? [];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (isCurrentBookEntry(data)) {
            final title = (data['bookTitle'] ?? '').toString();
            if (title.isNotEmpty) {
              return _progressText("Currently reading: $title");
            }
          }
        }

        return _progressText("No current book set");
      }),
    );
  }

  /// C — Chanting. Reads `lifetimeRounds` from the user document. The old
  /// sadhana-based "today" figure was removed: it only counted rounds typed
  /// into the sadhana form, so it contradicted the japa counter.
  ///
  /// Shown as the tall tile's big number ("rounds lifetime" under it): the
  /// same stream and the same reading as the old "Lifetime: N rounds" line.
  Widget _chantingProgress() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final raw = data?['lifetimeRounds'];
        final lifetime = raw is num ? raw.toInt() : 0;

        return GhostedTextLine(
          loading: snapshot.connectionState == ConnectionState.waiting,
          lineHeight: 53,
          ghostWidth: 90,
          child: CountUpText(
            value: lifetime,
            style: context.folkText.bigStat,
            ready: snapshot.connectionState != ConnectionState.waiting,
          ),
        );
      },
    );
  }

  /// Until a progress line's stream has delivered its first event, a ghost bar
  /// (same size as the text line) stands in for it, then cross-fades into the
  /// text. The streams, and the text built from them, are unchanged; an empty
  /// result still reads "No sessions yet" / "No current book set".
  Widget _ghostedProgress(AsyncSnapshot snapshot, Widget Function() line) {
    return GhostedTextLine(
      loading: snapshot.connectionState == ConnectionState.waiting,
      child: line(),
    );
  }

  /// The A-E letter, kept as the card's avatar (and the carrier for its unseen
  /// dot): a 44 dp frosted circle with the letter in the heading font.
  Widget _journeyLetterAvatar(String letter) {
    return Container(
      width: 44,
      height: 44,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: FolkColors.onGradientIconTile,
      ),
      child: Text(letter, style: context.folkText.cardTitle),
    );
  }

  Widget _progressText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: context.folkText.onGradientCaption,
    );
  }

  // ---------------------------------------------------------------------------
  // Card
  // ---------------------------------------------------------------------------

  /// One A-E tile of the mosaic. [tall] is the Chanting tile: it also shows
  /// its subtitle, and [stat] is its big number.
  Widget _journeyCard({
    required String letter,
    required String title,
    required String subtitle,
    required IconData icon,
    required FolkGradientStyle style,
    required Widget progress,
    required VoidCallback onTap,
    bool tall = false,
    String? statCaption,
    // Master Task 2026-09-10, Part 6 — optional; wraps the letter avatar
    // with an unseen dot for the limbs that have guide-driven content of
    // their own. Null (the default) renders exactly as before.
    Widget Function(Widget avatar)? wrapBadge,
  }) {
    final avatar = _journeyLetterAvatar(letter);

    return JourneyTile(
      style: style,
      title: title,
      subtitle: tall ? subtitle : null,
      watermark: icon,
      tall: tall,
      leading: wrapBadge != null ? wrapBadge(avatar) : avatar,
      stat: tall ? progress : null,
      statCaption: tall ? statCaption : null,
      line: tall ? null : progress,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    // The tab host paints the page background; this list only has to leave
    // room for the floating pill navigation under it.
    // One scope, so the progress-line ghosts pulse together; it only runs
    // while a ghost is showing.
    return GhostScope(
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          FolkSpace.pagePadding,
          0,
          FolkSpace.pagePadding,
          FloatingPillNavBar.reservedHeight(context) + FolkSpace.lg,
        ),
        physics: const BouncingScrollPhysics(),
        children: [
          EntryAnimation(
            index: 0,
            child: JourneyGreeting(
              firstName: _firstName(),
              loading: _userName == null,
            ),
          ),
          // Today's message — the same warm card Ask shows, from the shared
          // `DailyMessageService`. Showing it never marks anything seen; a
          // tap opens Ask, which does.
          EntryAnimation(
            index: 1,
            child: ValueListenableBuilder<DailyMessageState>(
              valueListenable: DailyMessageService.instance.state,
              builder: (context, state, _) =>
                  JourneyTodayMessage(state: state, onTap: _openAssistant),
            ),
          ),
          const EntryAnimation(index: 2, child: SectionDivider(label: 'ABCDE')),
          EntryAnimation(
            index: 3,
            child: JourneyPair(
              // Chanting: the tall tile on the left, as tall as the two short
              // tiles (Books, Association) stacked beside it.
              left: _journeyCard(
              letter: 'C',
              title: "Chanting",
              subtitle: "Track your japa rounds",
              icon: Icons.radio_button_checked_outlined,
              style: FolkFeatureGradients.chanting,
              progress: _chantingProgress(),
              tall: true,
              statCaption: "rounds lifetime",
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ChantingScreen(
                    uid: _uid,
                    userName: _userName ?? '',
                    role: _role ?? '',
                  ),
                ),
              ),
            ),
              right: JourneyStack(
                top: _journeyCard(
              letter: 'A',
              title: "Association",
              subtitle: "Connect with your guide",
              icon: Icons.people_alt_outlined,
              style: FolkFeatureGradients.association,
              progress: _associationProgress(),
              // Master Task 2026-09-10, Part 6 — unseen = a guide's own action
              // on one of this student's association records since they last
              // opened this screen.
              wrapBadge: (avatar) => UnseenFeatureBadge(
                featureKey: 'associations',
                timestampField: 'updatedAt',
                latestQuery: (uid) => FirebaseFirestore.instance
                    .collection('associations')
                    .where('studentUid', isEqualTo: uid)
                    .snapshots(),
                child: avatar,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AssociationScreen(
                    uid: _uid,
                    userName: _userName ?? '',
                    role: _role ?? '',
                  ),
                ),
              ),
            ),
                bottom: _journeyCard(
              letter: 'B',
              title: "Books",
              subtitle: "Read & track your progress",
              icon: Icons.menu_book_outlined,
              style: FolkFeatureGradients.books,
              progress: _booksProgress(),
              // Unseen = the guide assigned/updated a commitment on one of
              // this student's books since they last opened this screen
              // (`commitmentSetAt`, only when `commitmentSetBy == 'guide'` —
              // the student's own edits never light this up). Guide-marked
              // completion has no separate Timestamp field to compare against
              // (`endDate` is a plain date string, not a Firestore Timestamp)
              // so that action alone does not trigger this dot — a disclosed,
              // narrower scope for this one feature.
              wrapBadge: (avatar) => UnseenFeatureBadge(
                featureKey: 'bookCommitments',
                extractTimestamp: (data) {
                  if (data['commitmentSetBy'] != 'guide') return null;
                  final ts = data['commitmentSetAt'];
                  return ts is Timestamp ? ts : null;
                },
                latestQuery: (uid) => FirebaseFirestore.instance
                    .collection('booksRead')
                    .where('uid', isEqualTo: uid)
                    .snapshots(),
                child: avatar,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BooksSelectionScreen()),
              ),
            ),
              ),
            ),
          ),
          const SizedBox(height: FolkSpace.cardGap),
          EntryAnimation(
            index: 4,
            child: JourneyPair(
              left: _journeyCard(
              letter: 'D',
              title: "Devotional Service",
              subtitle: "Serve with devotion",
              icon: Icons.volunteer_activism_outlined,
              style: FolkFeatureGradients.devotionalService,
              progress: _progressText("Browse opportunities"),
              // Unseen = a guide's own change (new assignment, competence
              // verdict, or a status change THEY made) since this student
              // last opened this screen — excludes the student's own status
              // updates via `statusUpdatedBy`.
              wrapBadge: (avatar) => UnseenFeatureBadge(
                featureKey: 'serviceAssignments',
                extractTimestamp: (data) {
                  if (data['statusUpdatedBy'] == _uid) return null;
                  final ts = data['statusUpdatedAt'];
                  return ts is Timestamp ? ts : null;
                },
                latestQuery: (uid) => FirebaseFirestore.instance
                    .collection('serviceAssignments')
                    .where('studentUid', isEqualTo: uid)
                    .snapshots(),
                child: avatar,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ServiceBankScreen(
                    uid: _uid,
                    userName: _userName ?? '',
                    role: _role ?? '',
                  ),
                ),
              ),
            ),
              right: _journeyCard(
              letter: 'E',
              title: "Expeditions",
              subtitle: "Pilgrimages & retreats",
              icon: Icons.explore_outlined,
              style: FolkFeatureGradients.expeditions,
              progress: _progressText("View upcoming trips"),
              // Unseen = a new trip posted since this student last opened this
              // screen — every student sees the same `expeditions` list, no
              // per-student filter.
              wrapBadge: (avatar) => UnseenFeatureBadge(
                featureKey: 'expeditionTrips',
                timestampField: 'createdAt',
                latestQuery: (_) => FirebaseFirestore.instance
                    .collection('expeditions')
                    .snapshots(),
                child: avatar,
              ),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ExpeditionScreen(
                    uid: _uid,
                    userName: _userName ?? '',
                    role: _role ?? '',
                  ),
                ),
              ),
            ),
            ),
          ),
          const EntryAnimation(index: 5, child: SectionDivider(label: 'MODULES')),

          /// Phase 7 shells, below and visually separate from the five ABCDE
          /// cards. ABCDE is exactly five limbs of practice; these are content
          /// modules and must not be mistaken for a sixth.
          const EntryAnimation(index: 6, child: Phase7Section()),
        ],
      ),
    );
  }
}

/// Stand-in destination for journey sections that have no screen yet.
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkScaffold(
      title: title,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(FolkSpace.xxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.surfaceSecondary,
                ),
                child: Icon(Icons.hourglass_empty,
                    size: 44, color: colors.mutedText),
              ),
              const SizedBox(height: 16),
              Text("Coming Soon",
                  textAlign: TextAlign.center, style: text.screenTitle.copyWith(fontSize: 26)),
              const SizedBox(height: 8),
              Text(title, textAlign: TextAlign.center, style: text.small),
            ],
          ),
        ),
      ),
    );
  }
}
