import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkCard.dart';
import 'GradientCard.dart';

// Content pieces for the Profile and Insights destinations (Achievements,
// Notifications, Chanting Competition, Scorecard, History). Each one is the
// body of a card the screen used to build inline; the screens keep all data and
// navigation, these only draw.

// One badge on Achievements: the badge, its name and how many were earned.
// The count rises on first show; with "reduce animations" it is simply there.
class AchievementBadgeCard extends StatelessWidget {
  const AchievementBadgeCard({
    super.key,
    required this.badgeName,
    required this.count,
  });

  final String badgeName;
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final reduced = FolkMotion.reduced(context);
    return Container(
      width: 170,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
        gradient: FolkGradients.saffron,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          /// Badge icon
          Container(
            height: 120,
            width: 120,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: FolkColors.onGradientIconTile,
            ),
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Image.asset("assets/images/$badgeName.webp"),
            ),
          ),

          const SizedBox(height: 10),

          /// Badge name
          Text(
            badgeName.replaceAll("_", " ").toUpperCase(),
            textAlign: TextAlign.center,
            style: text.label.copyWith(color: FolkColors.onGradientSecondary),
          ),

          const SizedBox(height: 6),

          /// Count animation
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: count.toDouble()),
            duration:
                reduced ? Duration.zero : const Duration(milliseconds: 900),
            builder: (context, value, child) {
              return Text(
                value.toInt().toString(),
                style: text.stat,
              );
            },
          ),
        ],
      ),
    );
  }
}

// One notification switch: icon, title, a line of explanation, and a small
// spinner while the choice is being saved.
class PrefSwitchTile extends StatelessWidget {
  const PrefSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.busy,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final bool busy;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: EdgeInsets.zero,
      radius: FolkShape.tileRadius,
      // `FolkCard` supplies the `Material` the tile's ink needs (the earlier
      // splash-hidden-behind-the-fill fix), so the tap feedback is still seen.
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: Colors.white,
        activeTrackColor: FolkCalendarTokens.legendSubmitted,
        inactiveTrackColor: colors.switchOff,
        inactiveThumbColor: colors.mutedText,
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Row(
          children: [
            Icon(icon, size: 18, color: colors.mutedText),
            const SizedBox(width: 8),
            Expanded(child: Text(title, style: text.bodyStrong)),
            if (busy)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: colors.text),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(subtitle, style: text.caption),
        ),
      ),
    );
  }
}

// The collective total of a chanting challenge, on the coral gradient.
class ChallengeSummaryCard extends StatelessWidget {
  const ChallengeSummaryCard({
    super.key,
    required this.name,
    required this.dateText,
    required this.total,
    required this.target,
    required this.fraction,
  });

  final String name;
  final String dateText;
  final int total;
  final int target;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: FolkGradients.coral,
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name.isEmpty ? "Chanting Competition" : name,
            style: text.cardTitle,
          ),
          if (dateText.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(dateText, style: text.onGradientSmall),
          ],
          const SizedBox(height: 14),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              Text("$total", style: text.stat),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  " / $target rounds — together",
                  style: text.onGradientSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 8,
              backgroundColor: FolkColors.onGradientIconTile,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(FolkColors.onGradient),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Every student's own rounds add to this shared total. "
            "This is a group goal, not a personal one.",
            style: text.onGradientCaption.copyWith(fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// One student's rounds in a challenge, with a bar against the shared target.
class ContributionRow extends StatelessWidget {
  const ContributionRow({
    super.key,
    required this.name,
    required this.rounds,
    required this.fraction,
  });

  final String name;
  final int rounds;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkCard(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      radius: FolkShape.tileRadius,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.isEmpty ? "Unknown" : name,
                  style: text.bodyStrong,
                ),
              ),
              const SizedBox(width: 8),
              Text("$rounds rounds", style: text.chip),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: colors.surfaceSecondary,
              valueColor: const AlwaysStoppedAnimation<Color>(
                  FolkCalendarTokens.legendMissed),
            ),
          ),
        ],
      ),
    );
  }
}

// The summary shown once when a challenge has ended. [action] is its button.
class ChallengeResultCard extends StatelessWidget {
  const ChallengeResultCard({
    super.key,
    required this.achieved,
    required this.name,
    required this.total,
    required this.target,
    required this.topStudents,
    required this.topRounds,
    required this.action,
  });

  final bool achieved;
  final String name;
  final int total;
  final int target;
  final List<String> topStudents;
  final int topRounds;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkCard(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: achieved ? FolkGradients.saffron : null,
              color: achieved ? null : colors.surfaceSecondary,
            ),
            child: Icon(
              achieved ? Icons.emoji_events : Icons.flag_outlined,
              size: 34,
              color: achieved ? FolkColors.onGradient : colors.mutedText,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            achieved ? "Target reached!" : "Competition closed",
            textAlign: TextAlign.center,
            style: text.topBarTitle,
          ),
          const SizedBox(height: 4),
          Text(
            name.isEmpty ? "Chanting Competition" : name,
            textAlign: TextAlign.center,
            style: text.small,
          ),
          const SizedBox(height: 14),
          Text(
            "$total / $target rounds together",
            textAlign: TextAlign.center,
            style: text.bodyStrong,
          ),
          const SizedBox(height: 16),
          if (topStudents.isNotEmpty) ...[
            Text(
              topStudents.length == 1 ? "Top contributor" : "Top contributors",
              style: text.label,
            ),
            const SizedBox(height: 6),
            Text(
              "${topStudents.join(', ')} — $topRounds rounds",
              textAlign: TextAlign.center,
              style: text.bodyStrong,
            ),
            const SizedBox(height: 18),
          ],
          action,
        ],
      ),
    );
  }
}

// One tile on the Scorecard (Chanting, Book Reading, ...): the picture and the
// title on a gradient.
class ScoreCategoryCard extends StatelessWidget {
  const ScoreCategoryCard({
    super.key,
    required this.title,
    required this.image,
    required this.style,
    required this.onTap,
  });

  final String title;
  final String image;
  final FolkGradientStyle style;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return GradientCard(
      style: style,
      semanticLabel: title,
      onTap: onTap,
      child: Row(
        children: [
          Hero(
            tag: title,
            child: CircleAvatar(
              radius: 36,
              // Decoded at the size it is drawn (72 dp), not at the picture's
              // own 800-1400 px. All four pictures are landscape or square.
              backgroundImage: ResizeImage.resizeIfNeeded(
                null,
                (72 * MediaQuery.devicePixelRatioOf(context)).round(),
                AssetImage(image),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(title, style: text.cardTitle)),
        ],
      ),
    );
  }
}

// One past conversation in History: the day, a preview, and a chevron.
class HistorySessionTile extends StatelessWidget {
  const HistorySessionTile({
    super.key,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkCard(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      padding: const EdgeInsets.symmetric(vertical: 4),
      radius: FolkShape.tileRadius,
      // `FolkCard` is the Material the tile's ink paints on.
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: FolkGradients.violet,
          ),
          child: const Icon(Icons.forum_outlined,
              size: 20, color: FolkColors.onGradient),
        ),
        title: Text(label, style: text.bodyStrong),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.small,
        ),
        trailing:
            Icon(Icons.chevron_right, size: 20, color: colors.mutedText),
        onTap: onTap,
      ),
    );
  }
}

// One day's daily message in History, on the warm gradient.
class DailyHistoryCard extends StatelessWidget {
  const DailyHistoryCard({super.key, required this.label, required this.text});

  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = context.folkText;
    return Container(
      margin: const EdgeInsets.only(bottom: FolkSpace.cardGap),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: FolkGradients.sky,
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.wb_sunny_outlined,
                  size: 14, color: FolkColors.onGradientSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: style.onGradientSmall.copyWith(
                      color: FolkColors.onGradient,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style:
                style.body.copyWith(height: 1.4, color: FolkColors.onGradient),
          ),
        ],
      ),
    );
  }
}
