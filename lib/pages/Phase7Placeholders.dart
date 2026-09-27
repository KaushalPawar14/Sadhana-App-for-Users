import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';
import '../utils/UnseenFeatureBadge.dart';
import 'PodcastModulesScreen.dart';
import 'RduaFriendsScreen.dart';
import 'RduaScreen.dart';

/// Phase 7 — Content & Engagement placeholders.
///
/// **These are shells. Nothing here reads or writes data.**
///
/// Five of Phase 7's seven items are a single line of text in
/// FOLK_HANDOFF.md with no specification behind them — no content structure,
/// no data model, no source material. Rather than guess at a design, each
/// gets an honestly-labelled placeholder so the navigation exists and can be
/// filled in one item at a time once defined.
///
/// Every screen here states plainly that it is not built yet. There are no
/// fake buttons, no sample content, and no progress indicators that imply
/// something is loading — a student tapping one learns it is coming, and
/// nothing more.
///
/// Deliberately **not** scaffolded:
///   * **Japa card** — `ChantingScreen` already is the japa counter (108
///     beads, lifetime rounds, 30-day heatmap), shipped in Phase 4. A second
///     entry point would be a duplicate. Whether "Japa card" means something
///     different is a definition question, not a screen.
///   * **Competitions upgrade** — an upgrade to the existing competition
///     screen, so it is noted inline there rather than given its own shell.
class Phase7Item {
  final String title;
  final String description;
  final IconData icon;
  final Color colour;

  /// Verbatim from FOLK_HANDOFF.md, so the shell cannot drift from the spec.
  final String handoffLine;

  const Phase7Item({
    required this.title,
    required this.description,
    required this.icon,
    required this.colour,
    required this.handoffLine,
  });
}

/// The Phase 7 items that get a student-facing shell.
///
/// Empty since 2026-08-28 — RDUA was the only entry, and it is now built
/// (`RduaScreen`, 50 real topics / 100 chapters), promoted out of this list
/// exactly the way Podcast Modules was on 2026-08-13 (see the note below).
/// Left as a `const []` rather than deleted, so a future Phase 7 shell has
/// somewhere to go without re-deriving this file's own plumbing.
const List<Phase7Item> kPhase7Items = [];

// "Student conversational AI assistant" and "Prabhupada content feed" were
// both removed from this list on 2026-08-13 — they are built, not pending.
// The assistant is `AssistantScreen`; the feed is folded into it as starter
// questions, since it draws on the same corpus and the handoff defines no
// separate content structure to browse.
//
// ⚠️ The assistant's entry point moved on 2026-08-24 from a card on this
// screen to a persistent floating button (`utils/FloatingAssistantOverlay.dart`,
// wired at the app root in `main.dart`) — this file no longer references
// `AssistantScreen` at all. See that file for why.
//
// "Podcast Modules" was removed on 2026-08-13 for the same reason — it is
// `PodcastModulesScreen` now (FOLK-2/4/8/12/16, five freely-browsable
// categories with in-app audio playback).
//
// "RDUA Module" was removed the same way on 2026-08-28 — it is `RduaScreen`
// now (50 real topics, 100 chapters, reusing BookReaderPage entirely
// unmodified except its `isRdua` completion-tracking flag). `kPhase7Items`
// is empty as of this change — there is currently no undefined Phase 7 item
// left to shell.

/// The "Coming soon" section that sits below the five ABCDE cards.
///
/// A separate heading and separate cards, deliberately: ABCDE is exactly five
/// limbs of practice and these are not among them.
class Phase7Section extends StatelessWidget {
  const Phase7Section({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
        builder: (context, colorProvider, child)
    {
      return Container(
        color: colorProvider.color,
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 26, 24, 4),
            child: Text(
              "Coming to your journey",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
            child: Text(
              "Being prepared — not available yet",
              style: TextStyle(fontSize: 12, color: colorProvider.secondColor),
            ),
          ),
          ...kPhase7Items.map((item) => _card(context, item)),

          /// Live features sit apart from the shell above, and are styled to read
          /// as working rather than "coming soon".
          _rduaCard(context),
          _rduaFriendsCard(context),
          _podcastCard(context),
        ],
      ),
      );
    });
  }

  /// RDUA Friends — sibling entry point to RDUA Modules (Part 1 item 5),
  /// not nested inside `RduaScreen`. Friend requests, groups, and group
  /// voice rooms.
  Widget _rduaFriendsCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 5, 12, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2E7D32), Color(0xFF66BB6A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RduaFriendsScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Master Task 2026-09-10, Part 6 — unseen = a pending
                // friend request addressed to this student. Single
                // equality filter (`toUid`), `status` matched in Dart —
                // same no-composite-index convention `RduaFriendsScreen.
                // dart`'s own query already follows.
                UnseenFeatureBadge(
                  featureKey: 'friendRequests',
                  timestampField: 'createdAt',
                  extractTimestamp: (data) => data['status'] == 'pending'
                      ? data['createdAt'] as Timestamp?
                      : null,
                  latestQuery: (uid) => FirebaseFirestore.instance
                      .collection('friendRequests')
                      .where('toUid', isEqualTo: uid)
                      .snapshots(),
                  child: const Icon(Icons.people_alt_outlined,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "RDUA Friends",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        "Add friends, make groups, start a voice room",
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// RDUA Modules — 50 real topics, 100 chapters. Live, so styled like the
  /// podcast card rather than the muted "coming soon" shell.
  ///
  /// Takes no uid — the modules are not gated by level (product-owner
  /// instruction), so there is nothing about the student to look up before
  /// showing the list.
  Widget _rduaCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4527A0), Color(0xFF7B4FE0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RduaScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.school_outlined,
                    color: Colors.white, size: 26),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "RDUA Modules",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        "50 topics, 2 chapters each — open to everyone",
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// FOLK-2/4/8/12/16 audiobooks. Live, so styled like the assistant card
  /// rather than the muted shell cards.
  ///
  /// Takes no uid — the modules are not gated by level, so there is nothing
  /// about the student to look up.
  Widget _podcastCard(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 5),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF00695C), Color(0xFF00897B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PodcastModulesScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.headphones, color: Colors.white, size: 26),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Podcast Modules",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        "FOLK-2 to FOLK-16 — listen to all of them, any time",
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white70),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(BuildContext context, Phase7Item item) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => Phase7PlaceholderScreen(item)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    // Muted on purpose — these must not compete with the five
                    // live ABCDE cards above them.
                    color: item.colour.withOpacity(.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(item.icon, color: item.colour, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              item.title,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              "Coming soon",
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item.description,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A single placeholder screen. States what the feature will be and that it
/// does not exist yet. No controls, no data, nothing that pretends to work.
class Phase7PlaceholderScreen extends StatelessWidget {
  final Phase7Item item;

  const Phase7PlaceholderScreen(this.item, {super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            backgroundColor: colorProvider.color,
            elevation: 0,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text(
              item.title,
              style: TextStyle(
                color: colorProvider.secondColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: item.colour.withOpacity(.10),
                    ),
                    child: Icon(item.icon, size: 46, color: item.colour),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    "Not available yet",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    item.description,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: Colors.grey.shade700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    "Your guide will let you know when it is ready.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
