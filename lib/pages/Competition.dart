import 'package:flutter/foundation.dart' show ValueListenable, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:folk_app/pages/LeaderboardPage.dart';
import 'package:folk_app/scores/BestPerformer.dart';
import 'package:folk_app/utils/Snackbar.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkColors.dart';
import '../utils/InsightsData.dart';
import '../utils/ResultsDots.dart';
import '../utils/UnseenDot.dart';
import '../utils/SadhanaReportSource.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FloatingPillNavBar.dart';
import '../widgets/FolkCard.dart';
import '../widgets/InsightsGraphCarousel.dart';
import '../widgets/InsightsPeriodSwitch.dart';
import '../widgets/InsightTile.dart';

// The Insights tab: a Weekly / Monthly switch, a graph card the student swipes
// through (their own data only), and four tiles — Leaderboard wide, Weekly and
// Monthly Performance as squares, and Best Performer wide (violet).
class CompetitionPage extends StatefulWidget {
  final String role;

  // The student's name: their reports are filed under it.
  final String username;

  // Tests hand in their own reports and clock; the app never sets these.
  @visibleForTesting
  final Future<Reports> Function(String username)? loadReports;

  /// Tests hand in the results dot; the app reads it from `ResultsDots`.
  @visibleForTesting
  final Stream<bool>? resultsUnseen;
  @visibleForTesting
  final DateTime Function()? clock;

  const CompetitionPage({
    super.key,
    required this.role,
    this.username = '',
    this.loadReports,
    this.resultsUnseen,
    this.clock,
  });

  @override
  State<CompetitionPage> createState() => _CompetitionPageState();
}

class _CompetitionPageState extends State<CompetitionPage> {
  InsightPeriod _period = InsightPeriod.weekly;
  Reports? _reports;
  bool _failed = false;
  DateTime? _fetchedAt;
  ValueListenable<bool>? _tickerMode;

  DateTime _today() => (widget.clock ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    // The graphs follow the student's CURRENT category live: when a guide changes it, the other category's
    // reports stop counting and the graph set changes, at once.
    if (widget.loadReports == null) ReportCategory.instance.start();
    ReportCategory.instance.addListener(_categoryChanged);
    _load();
  }

  void _categoryChanged() {
    if (!mounted) return;
    setState(() => _reports = null); // the ghost, until the new category's reports are read
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = TickerMode.getNotifier(context);
    if (!identical(notifier, _tickerMode)) {
      _tickerMode?.removeListener(_shown);
      _tickerMode = notifier..addListener(_shown);
    }
  }

  // The tab is kept alive underneath the others; when it is shown again the
  // graphs are read again (quietly, keeping what is on screen) if they are old,
  // so a report submitted since shows up.
  void _shown() {
    if (!(_tickerMode?.value ?? false)) return;
    final at = _fetchedAt;
    if (at == null || _today().difference(at) > const Duration(seconds: 30)) {
      _load();
    }
  }

  @override
  void dispose() {
    ReportCategory.instance.removeListener(_categoryChanged);
    _tickerMode?.removeListener(_shown);
    super.dispose();
  }

  // The student's own reports from the collection of his CURRENT category (one read).
  Future<void> _load() async {
    _fetchedAt = _today();
    try {
      final name = widget.username.trim();
      final reports = await (widget.loadReports ?? fetchDateReports)(name);
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = _reports == null);
    }
  }

  void _retry() {
    setState(() => _failed = false);
    _load();
  }

  void _comingSoon() => showSnackbar(
        context,
        'Coming soon',
        Colors.yellow,
        Icons.watch_later_outlined,
      );

  // The Leaderboard (total points, the student's own scores and the best of each field, weekly or
  // monthly) is open to everyone and shows only the student's own category (FOLK, or Hostel & Localite)
  // and gender. Best Performer opens its page (the two weekly winners of the student's own group).
  void _open(String title) {
    if (title == 'Leaderboard') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => LeaderboardPage(username: widget.username)),
      );
    } else if (title == 'Best Performer') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => BestPerformerPage(username: widget.username)),
      );
    } else {
      _comingSoon();
    }
  }

  // Every tile is the same widget with the same layout (see `InsightTile`); the
  // wide one differs only in its width. Each is at least as tall as a square.
  InsightTile _tile(
    String title,
    String subtitle,
    FolkGradientStyle style,
    IconData icon,
    double minHeight,
  ) =>
      InsightTile(
        style: style,
        title: title,
        subtitle: subtitle,
        icon: icon,
        minHeight: minHeight,
        onTap: () => _open(title),
      );

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final columnWidth = (MediaQuery.of(context).size.width -
            2 * FolkSpace.pagePadding -
            FolkSpace.cardGap) /
        2;
    final reports = _reports;
    final graphs = reports == null ? kInsightGraphs.toList() : applicableGraphs(reports, ReportCategory.instance.role ?? widget.role);

    return Scaffold(
      // The tab host paints the page background (with the top fade).
      backgroundColor: Colors.transparent,
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          FolkSpace.pagePadding,
          FolkSpace.sm,
          FolkSpace.pagePadding,
          // Leaves room for the floating pill navigation.
          FloatingPillNavBar.reservedHeight(context) + 12,
        ),
        children: [
          EntryAnimation(
            index: 0,
            child: InsightsPeriodSwitch(
              period: _period,
              onChanged: (p) => setState(() => _period = p),
            ),
          ),
          const SizedBox(height: FolkSpace.cardGap),
          EntryAnimation(
            index: 1,
            child: _failed
                ? FolkCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Text("Couldn't load your reports just now.",
                            textAlign: TextAlign.center, style: text.small),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _retry,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  )
                : InsightsGraphCarousel(
                    graphs: graphs,
                    period: _period,
                    reports: reports,
                    today: _today(),
                  ),
          ),
          const SizedBox(height: FolkSpace.cardGap),
          // Leaderboard: full width, as tall as the squares below it.
          EntryAnimation(
            index: 2,
            child: StreamBuilder<bool>(
              // The orange dot while weekly / monthly results are published and not opened yet.
              stream: widget.resultsUnseen ?? ResultsDots.forCurrentUser()?.anyUnseen,
              builder: (context, snap) => UnseenBadge(
                key: const ValueKey('leaderboard-dot'),
                show: snap.data ?? false,
                offset: const Offset(7, 7),
                dotSize: 10,
                ringColor: FolkColors.onGradientIconTile,
                child: _tile(
                  'Leaderboard',
                  'Your group ranking',
                  FolkGradientStyle.saffron,
                  Icons.emoji_events,
                  columnWidth,
                ),
              ),
            ),
          ),
          const SizedBox(height: FolkSpace.cardGap),
          // Best Performer: full width like the Leaderboard card, in violet.
          EntryAnimation(
            index: 3,
            child: _tile(
              'Best Performer',
              "This week's winners",
              FolkFeatureGradients.bestPerformer,
              Icons.star,
              columnWidth,
            ),
          ),
        ],
      ),
    );
  }
}
