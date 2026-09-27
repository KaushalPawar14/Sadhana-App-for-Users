import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/UnseenFeatureBadge.dart';
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
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return _progressText(
          count > 0 ? "$count sessions this month" : "No sessions yet",
        );
      },
    );
  }

  /// B — Books. Filters on uid only; `isCurrentBook` is matched client-side so
  /// no composite index is required.
  Widget _booksProgress() {
    return StreamBuilder<QuerySnapshot>(
      stream: _booksStream,
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          if (data['isCurrentBook'] == true) {
            final title = (data['bookTitle'] ?? '').toString();
            if (title.isNotEmpty) {
              return _progressText("Currently reading: $title");
            }
          }
        }

        return _progressText("No current book set");
      },
    );
  }

  /// C — Chanting. Reads `lifetimeRounds` from the user document. The old
  /// sadhana-based "today" figure was removed: it only counted rounds typed
  /// into the sadhana form, so it contradicted the japa counter.
  Widget _chantingProgress() {
    return StreamBuilder<DocumentSnapshot>(
      stream: _userDocStream,
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final raw = data?['lifetimeRounds'];
        final lifetime = raw is num ? raw.toInt() : 0;

        return _progressText("Lifetime: $lifetime rounds");
      },
    );
  }

  Widget _journeyLetterAvatar(String letter, List<Color> gradient) {
    return CircleAvatar(
      radius: 22,
      backgroundColor: Colors.white,
      child: Text(
        letter,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: gradient.first,
        ),
      ),
    );
  }

  Widget _progressText(String text) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontStyle: FontStyle.italic,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Card
  // ---------------------------------------------------------------------------

  Widget _journeyCard({
    required String letter,
    required String title,
    required String subtitle,
    required IconData icon,
    required List<Color> gradient,
    required Widget progress,
    required VoidCallback onTap,
    // Master Task 2026-09-10, Part 6 — optional; wraps the letter avatar
    // with an unseen dot for the limbs that have guide-driven content of
    // their own. Null (the default) renders exactly as before.
    Widget Function(Widget avatar)? wrapBadge,
  }) {
    return Container(
      height: 220,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(.35),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Stack(
            children: [
              /// Faded watermark
              Positioned(
                right: 10,
                top: 50,
                child: Icon(
                  icon,
                  size: 120,
                  color: Colors.white.withOpacity(.15),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        wrapBadge != null
                            ? wrapBadge(_journeyLetterAvatar(letter, gradient))
                            : _journeyLetterAvatar(letter, gradient),
                        const Spacer(),
                        const Icon(
                          Icons.chevron_right,
                          color: Colors.white54,
                          size: 28,
                        ),
                      ],
                    ),

                    const Spacer(),

                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 14),
                    progress,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
    builder: (context, colorProvider, child) {
    return Container(
      color: colorProvider.color,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        physics: const BouncingScrollPhysics(),
        children: [
          _journeyCard(
            letter: 'A',
            title: "Association",
            subtitle: "Connect with your guide",
            icon: Icons.people_alt_outlined,
            gradient: const [Color(0xFFE65100), Color(0xFFFF8F00)],
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
          _journeyCard(
            letter: 'B',
            title: "Books",
            subtitle: "Read & track your progress",
            icon: Icons.menu_book_outlined,
            gradient: const [Color(0xFF4A148C), Color(0xFF7B1FA2)],
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
          _journeyCard(
            letter: 'C',
            title: "Chanting",
            subtitle: "Track your japa rounds",
            icon: Icons.radio_button_checked_outlined,
            gradient: const [Color(0xFF1B5E20), Color(0xFF388E3C)],
            progress: _chantingProgress(),
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
          _journeyCard(
            letter: 'D',
            title: "Devotional Service",
            subtitle: "Serve with devotion",
            icon: Icons.volunteer_activism_outlined,
            gradient: const [Color(0xFFB71C1C), Color(0xFFE53935)],
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
          _journeyCard(
            letter: 'E',
            title: "Expeditions",
            subtitle: "Pilgrimages & retreats",
            icon: Icons.explore_outlined,
            gradient: const [Color(0xFF01579B), Color(0xFF0288D1)],
            progress: _progressText("View upcoming trips"),
            // Unseen = a new trip posted since this student last opened this
            // screen — every student sees the same `expeditions` list, no
            // per-student filter.
            wrapBadge: (avatar) => UnseenFeatureBadge(
              featureKey: 'expeditionTrips',
              timestampField: 'createdAt',
              latestQuery: (_) =>
                  FirebaseFirestore.instance.collection('expeditions').snapshots(),
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

          /// Phase 7 shells, below and visually separate from the five ABCDE
          /// cards. ABCDE is exactly five limbs of practice; these are content
          /// modules and must not be mistaken for a sixth.
          const Phase7Section(),
        ],
      ),
    );
  });
  }
}

/// Stand-in destination for journey sections that have no screen yet.
class PlaceholderScreen extends StatelessWidget {
  final String title;

  const PlaceholderScreen({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
        builder: (context, colorProvider, child) {
      return Scaffold(
        appBar: AppBar(
          title: Text(title),
          backgroundColor: colorProvider.color,
          foregroundColor: colorProvider.secondColor,
          elevation: 1,
        ),
        backgroundColor: colorProvider.color,
        body: Center(

          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_empty,
                  size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              const Text(
                "Coming Soon",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(fontSize: 15, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
        });
  }
}
