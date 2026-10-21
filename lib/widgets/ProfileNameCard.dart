import 'package:flutter/cupertino.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'GradientCard.dart';

/// The text of the guide line: "Guide: NAME", or "Guide: Not assigned yet" when there is no guide (an empty name).
String guideLineText(Object? guideName) {
  final n = (guideName ?? '').toString().trim();
  return 'Guide: ${n.isEmpty ? 'Not assigned yet' : n}';
}

/// The sky-blue card at the top of the Profile: the avatar, the name, the category ("Stay at Hostel") and, directly under
/// the category, the guide line ("Guide: NAME"). Display only. The guide's name comes from the same instant source as
/// before (the `guideName` stamped on the student's own user document, plus the phone's copy), so the line needs no loading;
/// the card simply grows to fit a long name or a large text size (long names wrap to two lines, then end with "...").
class ProfileNameCard extends StatelessWidget {
  const ProfileNameCard({super.key, required this.name, required this.role, required this.guideName});

  final String name;
  final String role;
  final String guideName;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final initial = name.trim().isEmpty ? null : name.trim()[0].toUpperCase();
    return GradientCard(
      style: FolkGradientStyle.sky,
      decorate: false,
      padding: const EdgeInsets.all(FolkSpace.lg),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            alignment: Alignment.center,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: FolkColors.gradientPlayButton),
            child: initial == null ? const Icon(CupertinoIcons.person_alt, size: 28) : Text(initial, style: text.cardTitle.copyWith(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, key: const ValueKey('profile-name'), style: text.cardTitle.copyWith(fontSize: 22)),
                const SizedBox(height: 2),
                Text(role, key: const ValueKey('profile-category'), style: text.onGradientSmall),
                const SizedBox(height: 2),
                Text(
                  guideLineText(guideName),
                  key: const ValueKey('profile-guide-line'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: text.onGradientSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
