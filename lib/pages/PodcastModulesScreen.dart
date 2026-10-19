import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/ReadingLanguages.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/EpisodeTile.dart';
import '../widgets/MinHeightBox.dart';
import '../widgets/FolkChip.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/LanguageButton.dart';
import '../widgets/PodcastLoadingGhost.dart';
import '../widgets/MotionHelpers.dart';
import '../widgets/PlayPauseIcon.dart';
import '../widgets/PressScale.dart';
import '../widgets/RoundIconButton.dart';
import '../widgets/FolkErrorRetry.dart';

/// FOLK-2/4/8/12/16 — audiobook / podcast modules.
///
/// Replaces the "Podcast Modules" placeholder shell. The "RDUA" shell beside it
/// is deliberately untouched — RDUA remains skipped.
///
/// **Free browse — no gating.** Every student can open all five categories
/// regardless of their own chanting level. There is deliberately NO level
/// lookup anywhere in this file — access is never conditional on anything
/// read from `users/{uid}`. Confirmed as a product decision on 2026-08-13.
///
/// ⚠️ Follow-up task, 2026-09-10, Part 4 — this screen now DOES read (and
/// write) one field on `users/{uid}`: `readingPrefs.language`, the exact
/// same standing preference `BookPageList.dart` already uses for reading
/// language. This is not a gating mechanism and does not reintroduce the
/// concern above — it only selects which language's Dropbox link plays for
/// an episode every student can already reach; it never decides whether a
/// category or episode is reachable at all.
///
/// The default tab is **F2**, not the student's current level. A student's
/// FOLK-level does not exist as a field anywhere in Firestore — the only
/// `level` values in this app are book levels (`level-1..3`) and question
/// levels — so highlighting "their" level would have meant inventing a
/// rounds-to-bracket mapping. That is new level-computation logic, which this
/// task explicitly excludes. F2 first, and the other four are one tap away.
///
/// READS (never writes):
///   podcastModules/{F2|F4|F8|F12|F16}        -> episode_N_title, episode_N_duration
///   podcastModules/{level}_links             -> episode_N (Dropbox URL)
///
/// Audio plays **inside the app** via `just_audio`. Dropbox is never opened,
/// and no external player or browser is launched — there is no `url_launcher`
/// or `webview` import here on purpose.
class PodcastModulesScreen extends StatefulWidget {
  const PodcastModulesScreen({super.key});

  @override
  State<PodcastModulesScreen> createState() => _PodcastModulesScreenState();
}

class _PodcastModulesScreenState extends State<PodcastModulesScreen>
    with SingleTickerProviderStateMixin {
  /// Must match `PodcastLinkManagerPage.levels` in the Guide app.
  static const List<String> levels = ['F2', 'F4', 'F8', 'F12', 'F16'];

  static const Map<String, String> levelLabels = {
    'F2': 'FOLK-2',
    'F4': 'FOLK-4',
    'F8': 'FOLK-8',
    'F12': 'FOLK-12',
    'F16': 'FOLK-16',
  };

  late final TabController _tabController;

  /// UI only: true while the student drags the seek slider, so the progress
  /// bar follows the finger exactly instead of easing.
  bool _scrubbing = false;

  /// One key per level chip, so the chip row can scroll the selected chip into
  /// view when the tab changes by swiping.
  final List<GlobalKey> _chipKeys =
      List.generate(levels.length, (_) => GlobalKey());

  /// One player for the whole screen. A player per row would let two episodes
  /// play over each other, which is the single worst bug an audio list can have.
  final AudioPlayer _player = AudioPlayer();

  /// Identifies the loaded episode as "{level}#{number}" so the row that is
  /// playing can be highlighted without comparing URLs.
  String? _currentKey;
  String _currentTitle = '';

  /// Set when loading a URL fails, so the row can say so instead of silently
  /// doing nothing.
  String? _errorKey;

  bool _loading = false;

  /// Firestore-listener-in-build() fix (2026-09-09, size/perf task) — used
  /// to be constructed fresh directly in `build()`. Hoisted to a field,
  /// built once in `initState()` — this screen takes no `uid`/constructor
  /// args at all (see the class doc comment), so there is nothing that
  /// could ever change to justify rebuilding it.
  late Stream<QuerySnapshot<Map<String, dynamic>>> _modulesStream;

  /// Follow-up task, 2026-09-10, Part 4 — the student's reading language,
  /// reused unchanged from `BookPageList.dart` (same field, same map, same
  /// fallback to English). See this class's own doc comment for why
  /// reading it here does not reintroduce the "no access gating" concern.
  String _language = 'en';

  /// Kept in sync by hand with `BookPageList.dart`'s own
  /// `kSupportedLanguages` and the Guide app's `PodcastLinkManager.dart` /
  /// `BookLinkManager.dart` (no shared package between the two apps to
  /// hold one copy).
  static const Map<String, String> kSupportedLanguages = kReadingLanguages;

  /// Document that holds the URLs for a given category and reading
  /// language — identical convention to `PodcastLinkManager.dart`'s own
  /// `linksDocId` (English unsuffixed, every other language a sibling
  /// document).
  static String linksDocId(String level, String language) =>
      language == 'en' ? '${level}_links' : '${level}_links_$language';

  @override
  void initState() {
    super.initState();
    // initialIndex 0 == F2. See the class doc for why this is not the
    // student's own level.
    _tabController = TabController(length: levels.length, vsync: this);
    _tabController.addListener(_keepSelectedChipVisible);
    _modulesStream =
        FirebaseFirestore.instance.collection('podcastModules').snapshots();
    _loadLanguagePref();
  }

  Future<void> _loadLanguagePref() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (!mounted) return;
      final prefs = doc.data()?['readingPrefs'];
      final lang = prefs is Map ? prefs['language'] : null;
      if (lang is String && kSupportedLanguages.containsKey(lang)) {
        setState(() => _language = lang);
      }
    } catch (_) {
      // Non-fatal — the screen still works in English.
    }
  }

  /// Same standing preference `BookPageList.dart` writes — selecting a
  /// language on EITHER screen updates the other, which is the intended,
  /// coherent behaviour (Rule 1): one reading/listening language, not two
  /// independent, possibly-inconsistent settings.
  Future<void> _setLanguage(String language) async {
    if (language == _language) return;
    setState(() => _language = language);

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'readingPrefs': {'language': language},
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-fatal — the choice still applies for this session.
    }
  }

  @override
  void dispose() {
    // Releases the Android player; without this, audio keeps playing after the
    // screen is popped.
    _player.dispose();
    _tabController.removeListener(_keepSelectedChipVisible);
    _tabController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Playback
  // ---------------------------------------------------------------------------

  Future<void> _playEpisode({
    required String key,
    required String title,
    required String url,
  }) async {
    // Tapping the episode that is already loaded toggles it, rather than
    // restarting from zero — losing your place by tapping twice is infuriating
    // in a 40-minute lecture.
    if (_currentKey == key) {
      if (_player.playing) {
        await _player.pause();
      } else {
        await _player.play();
      }
      setState(() {});
      return;
    }

    setState(() {
      _loading = true;
      _errorKey = null;
      _currentKey = key;
      _currentTitle = title;
    });

    try {
      await _player.stop();
      await _player.setAudioSource(AudioSource.uri(Uri.parse(url)));
      if (!mounted) return;
      setState(() => _loading = false);
      await _player.play();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = key;
        _currentKey = null;
        _currentTitle = '';
      });
    }
  }

  /// mm:ss for the live position readout. Hours are folded into minutes, since
  /// no episode here is expected to reach an hour and "72:15" reads fine.
  String _fmt(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return "$minutes:${seconds.toString().padLeft(2, '0')}";
  }

  // ---------------------------------------------------------------------------
  // Data
  // ---------------------------------------------------------------------------

  /// Episode numbers present in a category, numerically sorted.
  ///
  /// Driven by the `_title` keys on the main document, so an episode with a
  /// link but no title is not shown — the list must never render a row whose
  /// label is blank. Any key that is not exactly `episode_<digits>_title` is
  /// ignored, so a stray field cannot crash this screen.
  List<int> _episodeNumbers(Map<String, dynamic>? data) {
    if (data == null) return [];

    final pattern = RegExp(r'^episode_(\d+)_title$');

    final numbers = <int>[];
    for (final entry in data.entries) {
      final match = pattern.firstMatch(entry.key);
      if (match != null && entry.value is String) {
        final title = (entry.value as String).trim();
        if (title.isNotEmpty) numbers.add(int.parse(match.group(1)!));
      }
    }

    numbers.sort();
    return numbers;
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  /// Keeps the selected level chip on screen when the tab changes by swiping.
  void _keepSelectedChipVisible() {
    if (_tabController.indexIsChanging) return;
    final chipContext = _chipKeys[_tabController.index].currentContext;
    if (chipContext == null) return;
    Scrollable.ensureVisible(
      chipContext,
      alignment: .5,
      duration: FolkMotion.of(chipContext, FolkMotion.navMorph),
      curve: FolkMotion.standard,
    );
  }

  /// Round back button, centred title, and a spacer the same width as the
  /// button so the title stays centred. Replaces the AppBar; "back" is the
  /// same pop the AppBar's own back arrow did.
  Widget _topBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, FolkSpace.xl, FolkSpace.pagePadding, 0),
      child: Row(
        children: [
          RoundIconButton(
            icon: Icons.chevron_left_rounded,
            iconSize: 26,
            semanticLabel: 'Back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Text(
              "Podcast Modules",
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.folkText.topBarTitle,
            ),
          ),
          // One compact button: shows the language (EN, हि, ગુ, తె) and moves to
          // the next one on each tap; the same `_setLanguage` write as before.
          LanguageButton(language: _language, onChanged: _setLanguage),
        ],
      ),
    );
  }

  /// The five level chips. They drive the same [TabController] the swipeable
  /// [TabBarView] uses, so tapping a chip and swiping stay in step. Every chip
  /// is enabled — no lock icons, no disabled states.
  Widget _levelChips() {
    return Padding(
      padding: const EdgeInsets.only(top: FolkSpace.lg),
      child: AnimatedBuilder(
        animation: _tabController.animation!,
        builder: (context, _) {
          final selectedIndex = _tabController.animation!.value.round();
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: FolkSpace.pagePadding),
            child: Row(
              children: [
                for (var i = 0; i < levels.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                        right: i == levels.length - 1 ? 0 : FolkSpace.sm),
                    child: FolkChip(
                      key: _chipKeys[i],
                      label: levelLabels[levels[i]] ?? levels[i],
                      selected: i == selectedIndex,
                      large: true,
                      onTap: () => _tabController.animateTo(i),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  static const double _countLabelHeight = PodcastLoadingGhost.countLabelHeight;

  Widget _episodeTile({
    required String level,
    required int number,
    required String title,
    required String duration,
    required String url,
  }) {
    final key = "$level#$number";
    final isCurrent = _currentKey == key;
    final hasAudio = url.trim().isNotEmpty;

    return EpisodeTile(
      title: title,
      duration: duration,
      hasAudio: hasAudio,
      isCurrent: isCurrent,
      isPlaying: isCurrent && _player.playing,
      isLoading: isCurrent && _loading,
      failed: _errorKey == key,
      onTap: hasAudio
          ? () => _playEpisode(key: key, title: title, url: url)
          : null,
    );
  }

  /// The now-playing bar: a floating pill over the list. Only rendered once
  /// something is loaded. Play/pause, the title, position / length, Stop and
  /// the draggable seek slider all work exactly as before.
  Widget _playerBar() {
    final colors = context.folk;
    final text = context.folkText;
    final foreground = colors.primaryFg;
    final fill = FolkGradients.saffron.colors.last;

    return Container(
      height: FolkShape.miniPlayerHeight,
      padding: const EdgeInsets.only(left: 10, right: 4),
      decoration: BoxDecoration(
        color: colors.primaryBg,
        borderRadius: BorderRadius.circular(FolkShape.miniPlayerRadius),
        boxShadow: [
          BoxShadow(
            color:
                colors.navShadow.withValues(alpha: colors.navShadow.a * 1.25),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: _player.playing ? 'Pause' : 'Play',
            excludeSemantics: true,
            child: PressScale(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  if (_player.playing) {
                    await _player.pause();
                  } else {
                    await _player.play();
                  }
                  if (mounted) setState(() {});
                },
                child: SizedBox(
                  width: FolkShape.touchTarget,
                  height: FolkShape.touchTarget,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: FolkGradients.saffron,
                      ),
                      child: PlayPauseIcon(
                        playing: _player.playing,
                        color: FolkColors.onGradient,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: SizedBox(
              height: FolkShape.miniPlayerHeight,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    child: Text(
                      _currentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyStrong
                          .copyWith(fontSize: 14, color: foreground),
                    ),
                  ),
                  // The seek slider keeps a full 48 dp tall drag zone; the
                  // title above it is not interactive, so they may overlap.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: FolkShape.touchTarget,
                    child: StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, snapshot) {
                        final total = _player.duration ?? Duration.zero;
                        final position = snapshot.data ?? Duration.zero;

                        // Clamped because a position can briefly exceed the
                        // reported duration while a stream is still
                        // resolving, and Slider throws if value > max.
                        final maxMs = total.inMilliseconds.toDouble();
                        final valueMs = position.inMilliseconds
                            .clamp(0, total.inMilliseconds);

                        return SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4,
                            activeTrackColor: fill,
                            inactiveTrackColor: FolkColors.miniPlayerTrack,
                            thumbColor: fill,
                            overlayColor: fill.withValues(alpha: .2),
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16),
                          ),
                          // The position arrives a few times a second; the bar
                          // eases between those readings. While the student
                          // drags, it follows the finger with no easing.
                          child: EasedProgress(
                            value: maxMs == 0 ? 0 : valueMs.toDouble(),
                            following: _scrubbing,
                            builder: (context, shown) => Slider(
                              value: maxMs == 0
                                  ? 0
                                  : shown.clamp(0.0, maxMs).toDouble(),
                              max: maxMs == 0 ? 1 : maxMs,
                              onChangeStart: (_) =>
                                  setState(() => _scrubbing = true),
                              onChangeEnd: (_) =>
                                  setState(() => _scrubbing = false),
                              onChanged: maxMs == 0
                                  ? null
                                  : (value) => _player.seek(
                                      Duration(milliseconds: value.round())),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Position and duration both come from the player, not from the
          // typed `episode_N_duration` string — the typed value is a human's
          // label and can be wrong; this is the real file.
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final total = _player.duration ?? Duration.zero;
              return Semantics(
                label: "${_fmt(position)} of ${_fmt(total)}",
                excludeSemantics: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _fmt(position),
                      style: text.caption.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _fmt(total),
                      style: text.caption.copyWith(
                        fontSize: 11,
                        color: foreground.withValues(alpha: .7),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            tooltip: "Stop",
            onPressed: () async {
              await _player.stop();
              if (!mounted) return;
              setState(() {
                _currentKey = null;
                _currentTitle = '';
              });
            },
            icon: Icon(Icons.close,
                size: 20, color: foreground.withValues(alpha: .7)),
          ),
        ],
      ),
    );
  }

  /// The mini-player's place at the bottom. It slides up (and fades in) when an
  /// episode is loaded and slides back down when it is stopped.
  Widget _playerSlot() {
    return Positioned(
      left: FolkSpace.pagePadding,
      right: FolkSpace.pagePadding,
      bottom: 24 + MediaQuery.paddingOf(context).bottom,
      child: SlideUpSwitcher(
        child: _currentKey != null ? _playerBar() : null,
      ),
    );
  }

  Widget _levelTab({
    required String level,
    required Map<String, dynamic>? episodesData,
    required Map<String, dynamic>? linksData,
    required double bottomPadding,
  }) {
    final colors = context.folk;
    final text = context.folkText;
    final numbers = _episodeNumbers(episodesData);

    if (numbers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.headphones_outlined,
                  size: 46, color: colors.disabledText),
              const SizedBox(height: 16),
              Text(
                "No episodes in ${levelLabels[level] ?? level} yet",
                textAlign: TextAlign.center,
                style: text.bodyStrong,
              ),
              const SizedBox(height: 8),
              Text(
                "New audio is added by your guide. Try another module above.",
                textAlign: TextAlign.center,
                style: text.small,
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.fromLTRB(
          FolkSpace.pagePadding, 0, FolkSpace.pagePadding, bottomPadding),
      children: [
        EntryAnimation(
          index: 3,
          child: Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: MinHeightBox(
              minHeight: _countLabelHeight,
              child: Text(
                (numbers.length == 1
                        ? "1 episode"
                        : "${numbers.length} episodes")
                    .toUpperCase(),
                style: text.label,
              ),
            ),
          ),
        ),
        for (var i = 0; i < numbers.length; i++)
          EntryAnimation(
            key: ValueKey("$level#${numbers[i]}"),
            index: 4 + i,
            child: _episodeTile(
              level: level,
              number: numbers[i],
              title: (episodesData?['episode_${numbers[i]}_title'] ?? '')
                  .toString(),
              duration: (episodesData?['episode_${numbers[i]}_duration'] ?? '')
                  .toString(),
              url: (linksData?['episode_${numbers[i]}'] ?? '').toString(),
            ),
          ),
      ],
    );
  }

  /// Cross-fades between the ghost, an error and the real list. All three fill
  /// the same body, so nothing moves.
  Widget _swap(String key, Widget child) {
    return AnimatedSwitcher(
      duration: FolkMotion.of(context, FolkMotion.ghostCrossFade),
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey<String>(key), child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    // Room under the last episode so the floating player never covers it.
    final listBottom = _currentKey != null
        ? FolkShape.miniPlayerHeight + 24 + safeBottom + FolkSpace.lg
        : 24 + safeBottom;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (colors.isDark
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark)
          .copyWith(statusBarColor: Colors.transparent),
      child: Scaffold(
        backgroundColor: colors.pageBackground,
        body: FolkPageBackground(
          child: SafeArea(
            bottom: false,
            child: Column(
              children: [
                EntryAnimation(index: 0, child: _topBar()),
                EntryAnimation(index: 1, child: _levelChips()),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    // One stream over the whole collection — ten small
                    // documents, so ten listeners would be worse. Mirrors the
                    // Guide app's manager.
                    stream: _modulesStream,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return _swap(
                          'error',
                          FolkErrorRetry(
                            message: "Couldn't load the modules just now.",
                            onRetry: () => setState(() {
                              _modulesStream = FirebaseFirestore.instance
                                  .collection('podcastModules')
                                  .snapshots();
                            }),
                          ),
                        );
                      }

                      if (!snapshot.hasData) {
                        return _swap('ghost', const PodcastLoadingGhost());
                      }

                      final docs = <String, Map<String, dynamic>>{};
                      for (final doc in snapshot.data!.docs) {
                        final data = doc.data();
                        if (data is Map<String, dynamic>) docs[doc.id] = data;
                      }

                      return _swap(
                          'real',
                          Stack(
                            children: [
                              Column(
                                children: [
                                  Expanded(
                                    child: TabBarView(
                                      controller: _tabController,
                                      children: levels
                                          .map((level) => _levelTab(
                                                level: level,
                                                episodesData: docs[level],
                                                linksData: docs[linksDocId(
                                                    level, _language)],
                                                bottomPadding: listBottom,
                                              ))
                                          .toList(),
                                    ),
                                  ),
                                ],
                              ),
                              _playerSlot(),
                            ],
                          ));
                    },
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
