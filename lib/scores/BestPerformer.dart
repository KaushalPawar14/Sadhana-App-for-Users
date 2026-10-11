import 'package:flutter/material.dart';

import '../models/BestPerformers.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/GradientCard.dart';
import '../widgets/ScoreWidgets.dart';

// Best performer: the two winners of the week in the student's OWN group (their
// category, FOLK or Hostel & Localite, and their gender), and the two of the week
// before. Decided on the server every Sunday for the week that just ended.
//
//   Most Improved      the biggest rise in weekly points over their own previous week
//   Commitment Keeper  the most days chanting at least their own commitment
//
// A winner who is the viewer gets a warm highlight. Nobody qualifying in a group is
// a friendly line, not an error.
class BestPerformerPage extends StatefulWidget {
  const BestPerformerPage({
    super.key,
    required this.username,
    @visibleForTesting this.loader,
  });

  // The signed-in student's name (the winners are named by it).
  final String username;

  @visibleForTesting
  final Future<BestPerformers> Function()? loader;

  @override
  State<BestPerformerPage> createState() => _BestPerformerPageState();
}

class _BestPerformerPageState extends State<BestPerformerPage> {
  late Future<BestPerformers> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<BestPerformers> _load() => (widget.loader ?? loadBestPerformers)();

  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: 'Best Performer',
      body: FutureBuilder<BestPerformers>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const LeaderboardGhost(rows: 3);
          }
          if (snap.hasError) {
            return _Message(
              text: "Couldn't load the winners just now.",
              action: TextButton(onPressed: _retry, child: const Text('Try again')),
            );
          }
          final data = snap.data!;
          if (data.isEmpty) {
            return const _Message(
              text: 'The first winners will appear after the weekly results, on Sunday morning.',
            );
          }
          return _Winners(data: data, username: widget.username);
        },
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FolkSpace.pagePadding),
        child: FolkCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emoji_events_outlined, size: 40, color: context.folk.mutedText),
              const SizedBox(height: 10),
              Text(text, textAlign: TextAlign.center, style: context.folkText.body),
              if (action != null) ...[const SizedBox(height: 8), action!],
            ],
          ),
        ),
      ),
    );
  }
}

class _Winners extends StatelessWidget {
  const _Winners({required this.data, required this.username});

  final BestPerformers data;
  final String username;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final week = data.thisWeek;
    final last = data.lastWeek;
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, FolkSpace.sm, FolkSpace.pagePadding, 40),
      children: [
        EntryAnimation(
          index: 0,
          child: Text("This week's winners", style: text.topBarTitle),
        ),
        const SizedBox(height: 4),
        Text('In your own group, decided every Sunday.', style: text.small),
        const SizedBox(height: FolkSpace.cardGap),
        EntryAnimation(
          index: 1,
          child: _WinnerCard(
            title: 'Most Improved',
            icon: Icons.trending_up_rounded,
            style: FolkGradientStyle.green,
            winner: week?.mostImproved,
            me: username,
            emptyText: 'No winner yet — a student needs 4 days of reports this week and points the week before.',
          ),
        ),
        const SizedBox(height: FolkSpace.cardGap),
        EntryAnimation(
          index: 2,
          child: _WinnerCard(
            title: 'Commitment Keeper',
            icon: Icons.verified_outlined,
            style: FolkGradientStyle.violet,
            winner: week?.commitmentKeeper,
            me: username,
            emptyText: 'No winner yet — set a chanting commitment in Profile and keep it.',
          ),
        ),
        const SizedBox(height: FolkSpace.xl),
        Text("Last week's winners", style: text.topBarTitle),
        const SizedBox(height: FolkSpace.cardGap),
        _LastWeekRow(label: 'Most Improved', winner: last?.mostImproved, me: username, hasWeek: last != null),
        const SizedBox(height: FolkSpace.cardGap),
        _LastWeekRow(label: 'Commitment Keeper', winner: last?.commitmentKeeper, me: username, hasWeek: last != null),
      ],
    );
  }
}

class _WinnerCard extends StatelessWidget {
  const _WinnerCard({
    required this.title,
    required this.icon,
    required this.style,
    required this.winner,
    required this.me,
    required this.emptyText,
  });

  final String title;
  final IconData icon;
  final FolkGradientStyle style;
  final BestWinner? winner;
  final String me;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final w = winner;
    if (w == null) {
      return FolkCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: context.folk.mutedText),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: text.bodyStrong),
                  const SizedBox(height: 4),
                  Text(emptyText, style: text.small),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final mine = w.name == me;
    return Semantics(
      container: true,
      label: '$title: ${w.name}. ${w.reason}',
      child: GradientCard(
        style: style,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: text.onGradientSmall)),
                if (mine) const Icon(Icons.celebration_outlined, size: 22),
              ],
            ),
            const SizedBox(height: 10),
            Text(w.name, style: text.cardTitle),
            if (w.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(w.reason, style: text.onGradientSmall),
            ],
            if (mine) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .55),
                  borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                ),
                child: Text(
                  "That's you! Well done — this was earned with your own steady effort.",
                  style: text.onGradientSmall,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LastWeekRow extends StatelessWidget {
  const _LastWeekRow({
    required this.label,
    required this.winner,
    required this.me,
    required this.hasWeek,
  });

  final String label;
  final BestWinner? winner;
  final String me;
  final bool hasWeek;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;
    final w = winner;
    final mine = w != null && w.name == me;
    return FolkCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      color: mine ? colors.surfaceSecondary : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.caption),
          const SizedBox(height: 4),
          if (w == null)
            Text(hasWeek ? 'No winner last week.' : 'No results for last week yet.', style: text.small)
          else ...[
            Text(mine ? '${w.name} — that was you!' : w.name, style: text.bodyStrong),
            if (w.reason.isNotEmpty) Text(w.reason, style: text.small),
          ],
        ],
      ),
    );
  }
}
