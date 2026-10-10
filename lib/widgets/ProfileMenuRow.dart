import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';
import 'ProfileMenuIconTile.dart';

// One row of the Profile menu: an icon tile, a title, a one-line subtitle and (when
// it can be tapped) a chevron. Press feedback is the shared 0.97 scale. With no
// [onTap] it is display only: no ripple, no chevron.
class ProfileMenuRow extends StatelessWidget {
  const ProfileMenuRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
      child: Row(
        children: [
          ProfileMenuIconTile(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyStrong),
                const SizedBox(height: 1),
                Text(subtitle, style: text.caption),
              ],
            ),
          ),
          if (onTap != null)
            Icon(Icons.chevron_right, size: 18, color: colors.mutedText),
        ],
      ),
    );
    if (onTap == null) return row;
    return PressScale(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(FolkShape.tileRadius),
          onTap: onTap,
          child: row,
        ),
      ),
    );
  }
}

// What "My Guide" says under its title: the guide's name (the adminUsers
// document id the student's `guideId` points at), or that none is assigned.
String guideRowSubtitle(Object? guideId) {
  final id = (guideId ?? '').toString().trim();
  return id.isEmpty ? 'Not assigned yet' : id;
}
