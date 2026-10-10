import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GradientCard.dart';
import 'PlayPauseIcon.dart';
import 'PressScale.dart';

// One podcast episode row: a round play / pause button, the title, the
// duration, and (when relevant) "not uploaded yet" or "could not play". The
// loaded episode is the saffron tile; the others are surface cards. The row is
// at least 72 dp tall and grows with large text, so nothing is ever clipped.
class EpisodeTile extends StatelessWidget {
  const EpisodeTile({
    super.key,
    required this.title,
    required this.duration,
    required this.hasAudio,
    required this.isCurrent,
    required this.isPlaying,
    required this.isLoading,
    required this.failed,
    required this.onTap,
  });

  final String title;
  final String duration;
  final bool hasAudio;
  final bool isCurrent;
  final bool isPlaying;
  final bool isLoading;
  final bool failed;

  // Null for an episode with no link yet: it is not tappable (better than a tap
  // that appears to do nothing).
  final VoidCallback? onTap;

  static const double minHeight = 72;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;

    // The loaded episode is the saffron tile; every other one is a surface.
    final primaryText = isCurrent ? FolkColors.onGradient : colors.text;
    final secondaryText =
        isCurrent ? FolkColors.onGradientSecondary : colors.mutedText;

    final playButton = Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: hasAudio && !isCurrent ? FolkGradients.green : null,
        color: !hasAudio
            ? colors.surfaceSecondary
            : isCurrent
                ? FolkColors.gradientPlayButton
                : null,
      ),
      child: Center(
        child: isCurrent && isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: FolkColors.onGradient,
                ),
              )
            : !hasAudio
                ? Icon(
                    Icons.hourglass_empty,
                    size: 22,
                    color: colors.disabledText,
                  )
                : PlayPauseIcon(
                    playing: isPlaying,
                    color: FolkColors.onGradient,
                  ),
      ),
    );

    final details = Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: text.bodyStrong.copyWith(height: 1.25, color: primaryText),
          ),
          const SizedBox(height: 3),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: FolkSpace.sm,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 12, color: secondaryText),
                  const SizedBox(width: 4),
                  // Duration is visible BEFORE playback, per spec.
                  Text(
                    duration.trim().isEmpty ? "—" : duration.trim(),
                    style: text.caption.copyWith(color: secondaryText),
                  ),
                ],
              ),
              if (!hasAudio)
                Text(
                  "not uploaded yet",
                  style: text.caption.copyWith(
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    color: secondaryText,
                  ),
                ),
              if (failed)
                Text(
                  "could not play — try again",
                  style: text.caption.copyWith(
                    fontSize: 11,
                    color: colors.calendarMissedText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    final row = Row(
      children: [
        playButton,
        const SizedBox(width: 14),
        details,
      ],
    );
    const tilePadding = EdgeInsets.symmetric(horizontal: 14, vertical: 12);
    final semanticLabel = "${isPlaying ? 'Pause' : 'Play'} $title";

    final Widget tile = isCurrent
        ? GradientCard(
            style: FolkGradientStyle.saffron,
            radius: FolkShape.tileRadius,
            padding: tilePadding,
            decorate: false,
            onTap: onTap,
            semanticLabel: semanticLabel,
            child: row,
          )
        : Semantics(
            button: hasAudio,
            label: semanticLabel,
            child: PressScale(
              enabled: hasAudio,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                  boxShadow: colors.cardShadows,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                    onTap: onTap,
                    child: Padding(padding: tilePadding, child: row),
                  ),
                ),
              ),
            ),
          );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: minHeight),
        child: AnimatedSwitcher(
          duration: FolkMotion.of(context, FolkMotion.ghostCrossFade),
          child: KeyedSubtree(key: ValueKey<bool>(isCurrent), child: tile),
        ),
      ),
    );
  }
}
