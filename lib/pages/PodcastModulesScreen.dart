import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../utils/ColorProvider.dart';

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
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _modulesStream;

  /// Follow-up task, 2026-09-10, Part 4 — the student's reading language,
  /// reused unchanged from `BookPageList.dart` (same field, same map, same
  /// fallback to English). See this class's own doc comment for why
  /// reading it here does not reintroduce the "no access gating" concern.
  String _language = 'en';

  /// Kept in sync by hand with `BookPageList.dart`'s own
  /// `kSupportedLanguages` and the Guide app's `PodcastLinkManager.dart` /
  /// `BookLinkManager.dart` (no shared package between the two apps to
  /// hold one copy).
  static const Map<String, String> kSupportedLanguages = {
    'en': 'English',
    'hi': 'हिन्दी',
    'gu': 'ગુજરાતી',
    'te': 'తెలుగు',
  };

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

  /// Same language-chip pattern `BookPageList.dart`'s reader uses, adapted
  /// to this screen's own plain white-card look rather than that screen's
  /// purple banner (there is no equivalent banner here to match).
  Widget _languageSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Listening language",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade600,
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
                selectedColor: const Color(0xFF00695C).withOpacity(.18),
                labelStyle: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                  color:
                      selected ? const Color(0xFF00695C) : Colors.black87,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _episodeTile({
    required String level,
    required int number,
    required String title,
    required String duration,
    required String url,
  }) {
    final key = "$level#$number";
    final isCurrent = _currentKey == key;
    final isPlaying = isCurrent && _player.playing;
    final failed = _errorKey == key;
    final hasAudio = url.trim().isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isCurrent ? const Color(0xFF00695C) : Colors.grey.shade200,
          width: isCurrent ? 1.6 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // An episode with no link yet is not tappable. Better than a tap that
          // appears to do nothing.
          onTap: hasAudio
              ? () => _playEpisode(key: key, title: title, url: url)
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasAudio
                        ? const Color(0xFF00695C).withOpacity(.10)
                        : Colors.grey.shade100,
                  ),
                  child: Center(
                    child: isCurrent && _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            !hasAudio
                                ? Icons.hourglass_empty
                                : isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                            color: hasAudio
                                ? const Color(0xFF00695C)
                                : Colors.grey.shade500,
                          ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.schedule,
                              size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          // Duration is visible BEFORE playback, per spec.
                          Text(
                            duration.trim().isEmpty ? "—" : duration.trim(),
                            style: TextStyle(
                                fontSize: 12, color: Colors.grey.shade700),
                          ),
                          if (!hasAudio) ...[
                            const SizedBox(width: 8),
                            Text(
                              "not uploaded yet",
                              style: TextStyle(
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                          if (failed) ...[
                            const SizedBox(width: 8),
                            Text(
                              "could not play — try again",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ],
                        ],
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

  /// The now-playing bar. Only rendered once something is loaded, so the list
  /// is not permanently shortened by an empty player.
  Widget _playerBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, -3),
          )
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () async {
                  if (_player.playing) {
                    await _player.pause();
                  } else {
                    await _player.play();
                  }
                  if (mounted) setState(() {});
                },
                icon: Icon(
                  _player.playing ? Icons.pause_circle : Icons.play_circle,
                  size: 38,
                  color: const Color(0xFF00695C),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    // Position and duration both come from the player, not from
                    // the typed `episode_N_duration` string — the typed value is
                    // a human's label and can be wrong; this is the real file.
                    StreamBuilder<Duration>(
                      stream: _player.positionStream,
                      builder: (context, snapshot) {
                        final position = snapshot.data ?? Duration.zero;
                        final total = _player.duration ?? Duration.zero;
                        return Text(
                          "${_fmt(position)} / ${_fmt(total)}",
                          style: TextStyle(
                              fontSize: 11.5, color: Colors.grey.shade600),
                        );
                      },
                    ),
                  ],
                ),
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
                icon: Icon(Icons.close, color: Colors.grey.shade600),
              ),
            ],
          ),
          StreamBuilder<Duration>(
            stream: _player.positionStream,
            builder: (context, snapshot) {
              final total = _player.duration ?? Duration.zero;
              final position = snapshot.data ?? Duration.zero;

              // Clamped because a position can briefly exceed the reported
              // duration while a stream is still resolving, and Slider throws
              // if value > max.
              final maxMs = total.inMilliseconds.toDouble();
              final valueMs =
                  position.inMilliseconds.clamp(0, total.inMilliseconds);

              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: maxMs == 0 ? 0 : valueMs.toDouble(),
                  max: maxMs == 0 ? 1 : maxMs,
                  activeColor: const Color(0xFF00695C),
                  inactiveColor: Colors.grey.shade300,
                  onChanged: maxMs == 0
                      ? null
                      : (value) =>
                          _player.seek(Duration(milliseconds: value.round())),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _levelTab({
    required String level,
    required Map<String, dynamic>? episodesData,
    required Map<String, dynamic>? linksData,
  }) {
    final numbers = _episodeNumbers(episodesData);

    if (numbers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.headphones_outlined,
                  size: 46, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                "No episodes in ${levelLabels[level] ?? level} yet",
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                "New audio is added by your guide. Try another module above.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            numbers.length == 1 ? "1 episode" : "${numbers.length} episodes",
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
          ),
        ),
        ...numbers.map(
          (n) => _episodeTile(
            level: level,
            number: n,
            title: (episodesData?['episode_${n}_title'] ?? '').toString(),
            duration: (episodesData?['episode_${n}_duration'] ?? '').toString(),
            url: (linksData?['episode_$n'] ?? '').toString(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(
      builder: (context, colorProvider, child) {
        return Scaffold(
          backgroundColor: colorProvider.color,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            iconTheme: IconThemeData(color: colorProvider.secondColor),
            title: Text(
              "Podcast Modules",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 20,
              ),
            ),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF00695C),
              unselectedLabelColor: colorProvider.secondColor.withOpacity(.7),
              indicatorColor: const Color(0xFF00695C),
              labelStyle: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w700),
              // Every tab is enabled. No lock icons, no disabled states.
              tabs: levels
                  .map((l) => Tab(text: levelLabels[l] ?? l))
                  .toList(),
            ),
          ),
          body: StreamBuilder<QuerySnapshot>(
            // One stream over the whole collection — ten small documents, so
            // ten listeners would be worse. Mirrors the Guide app's manager.
            stream: _modulesStream,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      "Could not load the modules just now.",
                      style: TextStyle(color: colorProvider.secondColor),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }

              final docs = <String, Map<String, dynamic>>{};
              for (final doc in snapshot.data!.docs) {
                final data = doc.data();
                if (data is Map<String, dynamic>) docs[doc.id] = data;
              }

              return Column(
                children: [
                  _languageSelector(),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: levels
                          .map((level) => _levelTab(
                                level: level,
                                episodesData: docs[level],
                                linksData: docs[linksDocId(level, _language)],
                              ))
                          .toList(),
                    ),
                  ),
                  if (_currentKey != null) _playerBar(),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
