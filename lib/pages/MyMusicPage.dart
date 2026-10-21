import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/MusicData.dart';
import '../widgets/EntryAnimation.dart';
import '../widgets/FolkCard.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkErrorRetry.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/FolkSegmented.dart';
import '../widgets/GhostPlaceholder.dart';

/// Profile -> My Music: the curriculum the HODs and Guides set (live), with the student's progress.
///
/// Each instrument is an expandable card: its name, "3 of 7", a progress bar, a small link icon (no visible URL) when it
/// has a YouTube link, and a "Completed" badge once every checkpoint is ticked (unticking one removes it). The checkpoints
/// are tick boxes in the HODs' order; the student can tick and untick their own, and their guide can too (no approval; who
/// ticked and when is shown subtly under the tick). "Others" lets the student add instruments of their own with a level.
class MyMusicPage extends StatefulWidget {
  const MyMusicPage({super.key, this.store, this.uid, this.openLink});

  /// Test seams: where the data lives, whose it is, and how a link is opened (the app uses Firestore, the signed-in
  /// student and the phone's browser / YouTube app).
  @visibleForTesting
  final MusicStore? store;
  @visibleForTesting
  final String? uid;
  @visibleForTesting
  final Future<bool> Function(Uri uri)? openLink;

  @override
  State<MyMusicPage> createState() => _MyMusicPageState();
}

class _MyMusicPageState extends State<MyMusicPage> {
  late final MusicStore _store = widget.store ?? FirestoreMusicStore();
  late final String _uid = widget.uid ?? FirebaseAuth.instance.currentUser!.uid;
  late Stream<List<MusicInstrument>> _curriculum = _store.curriculum();
  late Stream<MusicProgress> _progress = _store.progress(_uid);
  final Set<String> _open = {};

  void _retry() => setState(() {
        _curriculum = _store.curriculum();
        _progress = _store.progress(_uid);
      });

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _tick(String checkpointId, bool ticked) async {
    try {
      await _store.setTick(_uid, checkpointId, ticked, by: 'student', byName: '');
    } catch (_) {
      _say("Couldn't save that tick. Check your connection and try again.");
    }
  }

  Future<void> _openLink(String link) async {
    final uri = Uri.tryParse(link);
    var ok = false;
    if (uri != null) {
      try {
        ok = await (widget.openLink ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(uri);
      } catch (_) {}
    }
    if (!ok) _say("Couldn't open the link.");
  }

  Future<void> _saveOthers(List<OtherInstrument> others) async {
    try {
      await _store.saveOthers(_uid, others);
    } catch (_) {
      _say("Couldn't save that. Check your connection and try again.");
    }
  }

  Future<void> _editOther(List<OtherInstrument> all, {OtherInstrument? existing}) async {
    final result = await showDialog<OtherInstrument>(context: context, builder: (_) => _OtherDialog(existing: existing));
    if (result == null) return;
    final next = existing == null ? [...all, result] : [for (final o in all) o.id == result.id ? result : o];
    await _saveOthers(next);
  }

  Future<void> _removeOther(List<OtherInstrument> all, OtherInstrument o) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = ctx.folk;
        final text = ctx.folkText;
        return AlertDialog(
          key: const ValueKey('music-remove-dialog'),
          shape: FolkDialog.shape(),
          title: Text('Remove ${o.name}?', style: text.topBarTitle),
          content: Text('It will be removed from your music list.', style: text.body),
          actions: [
            TextButton(style: FolkDialog.quietButton(colors, text), onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            TextButton(key: const ValueKey('music-remove-confirm'), style: FolkDialog.dangerButton(colors, text), onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
          ],
        );
      },
    );
    if (sure == true) await _saveOthers([for (final x in all) if (x.id != o.id) x]);
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'My Music',
      body: StreamBuilder<List<MusicInstrument>>(
        stream: _curriculum,
        builder: (context, cur) {
          if (cur.hasError) return FolkErrorRetry(message: "Couldn't load your music just now.", onRetry: _retry);
          if (!cur.hasData) return const _MusicGhost();
          final instruments = cur.data!;
          return StreamBuilder<MusicProgress>(
            stream: _progress,
            builder: (context, prog) {
              if (prog.hasError) return FolkErrorRetry(message: "Couldn't load your music just now.", onRetry: _retry);
              final progress = prog.data ?? MusicProgress.empty;
              return ListView(
                key: const ValueKey('music-list'),
                padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding, FolkSpace.md, FolkSpace.pagePadding, 32),
                children: [
                  Text('Tick each checkpoint as you learn it. Your guide can tick it for you too.', key: const ValueKey('music-intro'), style: text.small),
                  const SizedBox(height: FolkSpace.lg),
                  if (instruments.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: FolkSpace.xl),
                      child: Text('No instruments have been set up yet.', key: const ValueKey('music-empty'), textAlign: TextAlign.center, style: text.small),
                    ),
                  for (var i = 0; i < instruments.length; i++)
                    EntryAnimation(
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: FolkSpace.cardGap),
                        child: _InstrumentCard(
                          key: ValueKey('music-instrument-${instruments[i].id}'),
                          instrument: instruments[i],
                          progress: progress,
                          expanded: _open.contains(instruments[i].id),
                          onToggleOpen: () => setState(() => _open.contains(instruments[i].id) ? _open.remove(instruments[i].id) : _open.add(instruments[i].id)),
                          onTick: _tick,
                          onLink: _openLink,
                        ),
                      ),
                    ),
                  const SizedBox(height: FolkSpace.md),
                  _OthersSection(
                    others: progress.others,
                    onAdd: () => _editOther(progress.others),
                    onEdit: (o) => _editOther(progress.others, existing: o),
                    onRemove: (o) => _removeOther(progress.others, o),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------------------------- an instrument card
class _InstrumentCard extends StatelessWidget {
  const _InstrumentCard({super.key, required this.instrument, required this.progress, required this.expanded, required this.onToggleOpen, required this.onTick, required this.onLink});

  final MusicInstrument instrument;
  final MusicProgress progress;
  final bool expanded;
  final VoidCallback onToggleOpen;
  final Future<void> Function(String checkpointId, bool ticked) onTick;
  final Future<void> Function(String link) onLink;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final total = instrument.checkpoints.length;
    final done = progress.done(instrument);
    final completed = progress.completed(instrument);
    return FolkCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the header: tapping anywhere on it opens / closes the card (the link icon is its own button)
          Semantics(
            button: true,
            expanded: expanded,
            label: '${instrument.name}, $done of $total',
            excludeSemantics: true,
            child: InkWell(
              key: ValueKey('music-header-${instrument.id}'),
              onTap: onToggleOpen,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(FolkSpace.lg, FolkSpace.md, FolkSpace.sm, FolkSpace.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(instrument.name, style: text.bodyStrong.copyWith(fontSize: 17)),
                        ),
                        if (completed) ...[
                          const _CompletedBadge(),
                          const SizedBox(width: FolkSpace.xs),
                        ],
                        if (instrument.hasLink)
                          IconButton(
                            key: ValueKey('music-link-${instrument.id}'),
                            tooltip: 'Open the lessons',
                            constraints: const BoxConstraints(minWidth: FolkShape.touchTarget, minHeight: FolkShape.touchTarget),
                            icon: Icon(Icons.link_rounded, size: 22, color: colors.text),
                            onPressed: () => onLink(instrument.link),
                          ),
                        AnimatedRotation(
                          turns: expanded ? .5 : 0,
                          duration: FolkMotion.of(context, FolkMotion.navMorph),
                          curve: FolkMotion.out,
                          child: Icon(Icons.keyboard_arrow_down_rounded, size: 26, color: colors.mutedText),
                        ),
                      ],
                    ),
                    const SizedBox(height: FolkSpace.xs),
                    Text(total == 0 ? 'No checkpoints yet' : '$done of $total', key: ValueKey('music-count-${instrument.id}'), style: text.caption),
                    const SizedBox(height: FolkSpace.sm),
                    _ProgressBar(key: ValueKey('music-bar-${instrument.id}'), fraction: total == 0 ? 0 : done / total, completed: completed),
                  ],
                ),
              ),
            ),
          ),
          // The checkpoints open with a gentle size animation (none with "reduce animations": an AnimatedSize with a zero
          // duration re-lays itself out, so it is simply not used then).
          _expandable(
            context,
            expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(FolkSpace.sm, 0, FolkSpace.sm, FolkSpace.sm),
                    child: Column(
                      children: [
                        for (final c in instrument.checkpoints)
                          _CheckpointRow(
                            key: ValueKey('music-cp-${c.id}'),
                            checkpoint: c,
                            tick: progress.ticks[c.id],
                            onChanged: (v) => onTick(c.id, v),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

Widget _expandable(BuildContext context, Widget child) => FolkMotion.reduced(context)
    ? child
    : AnimatedSize(duration: FolkMotion.navMorph, curve: FolkMotion.out, alignment: Alignment.topCenter, child: child);

class _CompletedBadge extends StatelessWidget {
  const _CompletedBadge();

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      key: const ValueKey('music-completed'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(gradient: FolkGradients.green, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_rounded, size: 14, color: FolkColors.onGradient),
          const SizedBox(width: 4),
          Text('Completed', style: text.caption.copyWith(color: FolkColors.onGradient, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({super.key, required this.fraction, required this.completed});

  final double fraction;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return Semantics(
      label: 'Progress',
      value: '${(fraction * 100).round()} percent',
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Container(
          height: 8,
          color: colors.surfaceSecondary,
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: fraction.clamp(0, 1)),
            duration: FolkMotion.of(context, FolkMotion.ringFill),
            curve: FolkMotion.out,
            builder: (context, f, _) => FractionallySizedBox(
              widthFactor: f,
              child: DecoratedBox(
                key: const ValueKey('music-bar-fill'),
                decoration: BoxDecoration(gradient: completed ? FolkGradients.green : FolkGradients.violet, borderRadius: BorderRadius.circular(6)),
                child: const SizedBox(height: 8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckpointRow extends StatelessWidget {
  const _CheckpointRow({super.key, required this.checkpoint, required this.tick, required this.onChanged});

  final MusicCheckpoint checkpoint;
  final MusicTick? tick;
  final ValueChanged<bool> onChanged;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "You · 12 Oct" / "Madhava Das · 12 Oct": who ticked it and when, shown subtly.
  String? get _by {
    final t = tick;
    if (t == null) return null;
    final who = t.byStudent ? 'You' : (t.byName.isEmpty ? 'Your guide' : t.byName);
    final at = t.at;
    return at == null ? who : '$who · ${at.day} ${_months[at.month - 1]}';
  }

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final ticked = tick != null;
    return Semantics(
      checked: ticked,
      inMutuallyExclusiveGroup: false,
      label: checkpoint.title,
      excludeSemantics: true,
      onTap: () => onChanged(!ticked),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onChanged(!ticked),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: FolkSpace.sm, vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _TickBox(key: ValueKey('music-box-${checkpoint.id}'), ticked: ticked),
                const SizedBox(width: FolkSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(checkpoint.title, style: text.body),
                      if (_by != null) Text(_by!, key: ValueKey('music-by-${checkpoint.id}'), style: text.caption.copyWith(fontSize: 11)),
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

/// A rounded tick box: empty with a hairline border, or the green gradient with a check.
class _TickBox extends StatelessWidget {
  const _TickBox({super.key, required this.ticked});

  final bool ticked;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    return AnimatedContainer(
      duration: FolkMotion.of(context, FolkMotion.press),
      curve: FolkMotion.out,
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        gradient: ticked ? FolkGradients.green : null,
        borderRadius: BorderRadius.circular(8),
        border: ticked ? null : Border.all(color: colors.mutedText.withValues(alpha: .6), width: 1.6),
      ),
      child: ticked ? const Icon(Icons.check_rounded, size: 18, color: FolkColors.onGradient) : null,
    );
  }
}

// ----------------------------------------------------------------------------------------------------------- Others
class _OthersSection extends StatelessWidget {
  const _OthersSection({required this.others, required this.onAdd, required this.onEdit, required this.onRemove});

  final List<OtherInstrument> others;
  final VoidCallback onAdd;
  final ValueChanged<OtherInstrument> onEdit;
  final ValueChanged<OtherInstrument> onRemove;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final colors = context.folk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Others', style: text.topBarTitle)),
            TextButton.icon(
              key: const ValueKey('music-add-other'),
              style: TextButton.styleFrom(minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget), foregroundColor: colors.text),
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: FolkSpace.xs),
        if (others.isEmpty)
          Text('Play something else? Add it here with your level.', key: const ValueKey('music-others-empty'), style: text.small)
        else
          for (final o in others)
            Padding(
              padding: const EdgeInsets.only(bottom: FolkSpace.sm),
              child: FolkCard(
                key: ValueKey('music-other-${o.id}'),
                padding: const EdgeInsets.fromLTRB(FolkSpace.lg, FolkSpace.sm, FolkSpace.sm, FolkSpace.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(o.name, style: text.bodyStrong),
                          Text(o.level.label, key: ValueKey('music-other-level-${o.id}'), style: text.caption),
                        ],
                      ),
                    ),
                    IconButton(
                      key: ValueKey('music-edit-${o.id}'),
                      tooltip: 'Edit',
                      constraints: const BoxConstraints(minWidth: FolkShape.touchTarget, minHeight: FolkShape.touchTarget),
                      icon: Icon(Icons.edit_outlined, size: 20, color: colors.text),
                      onPressed: () => onEdit(o),
                    ),
                    IconButton(
                      key: ValueKey('music-delete-${o.id}'),
                      tooltip: 'Remove',
                      constraints: const BoxConstraints(minWidth: FolkShape.touchTarget, minHeight: FolkShape.touchTarget),
                      icon: Icon(Icons.delete_outline_rounded, size: 20, color: colors.text),
                      onPressed: () => onRemove(o),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}

/// Add / edit one of the student's own instruments: a name and a level (Basic / Intermediate / Expert).
class _OtherDialog extends StatefulWidget {
  const _OtherDialog({this.existing});

  final OtherInstrument? existing;

  @override
  State<_OtherDialog> createState() => _OtherDialogState();
}

class _OtherDialogState extends State<_OtherDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late MusicLevel _level = widget.existing?.level ?? MusicLevel.basic;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please write the instrument');
      return;
    }
    Navigator.pop(context, OtherInstrument(id: widget.existing?.id ?? newMusicId('o'), name: name.length > 60 ? name.substring(0, 60) : name, level: _level));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return AlertDialog(
      key: const ValueKey('music-other-dialog'),
      shape: FolkDialog.shape(),
      scrollable: true,
      title: Text(widget.existing == null ? 'Add an instrument' : 'Edit instrument', style: text.topBarTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            key: const ValueKey('music-other-name'),
            controller: _name,
            textCapitalization: TextCapitalization.words,
            maxLength: 60,
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            decoration: FolkDialog.field(context, label: 'Instrument', hint: 'e.g. Flute').copyWith(errorText: _error, counterText: ''),
          ),
          const SizedBox(height: FolkSpace.lg),
          Text('Your level', style: text.caption),
          const SizedBox(height: FolkSpace.sm),
          FolkSegmented<MusicLevel>(
            key: const ValueKey('music-other-level'),
            segments: [for (final l in MusicLevel.values) FolkSegment(value: l, label: l.label)],
            value: _level,
            onChanged: (l) => setState(() => _level = l),
          ),
        ],
      ),
      actions: [
        TextButton(key: const ValueKey('music-other-cancel'), style: FolkDialog.quietButton(colors, text), onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(key: const ValueKey('music-other-save'), style: FolkDialog.primaryButton(colors, text), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _MusicGhost extends StatelessWidget {
  const _MusicGhost();

  @override
  Widget build(BuildContext context) {
    return GhostScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(FolkSpace.pagePadding),
        children: [
          for (var i = 0; i < 3; i++) ...[
            const GhostPlaceholder(width: double.infinity, height: 96),
            const SizedBox(height: FolkSpace.cardGap),
          ],
        ],
      ),
    );
  }
}
