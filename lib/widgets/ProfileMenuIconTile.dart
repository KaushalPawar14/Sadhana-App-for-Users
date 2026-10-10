import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTokens.dart';

// The icon tile of a Profile menu row: a 42 dp dark tile (the same in both
// themes) with the icon painted in the golden-orange saffron gradient. Six
// static icons, so a ShaderMask is fine.
class ProfileMenuIconTile extends StatelessWidget {
  const ProfileMenuIconTile(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: FolkColors.profileIconTile,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) =>
            FolkGradients.profileMenuIcon.createShader(bounds),
        child: Icon(icon, size: 20, color: Colors.white),
      ),
    );
  }
}
