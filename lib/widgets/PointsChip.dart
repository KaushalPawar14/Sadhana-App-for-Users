import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';

/// The small chip in a Sadhana question's card: "+50 pts" (the app's gold) or "×1.5" (the app's violet), ink text, the
/// same in light and dark like the other gradient tiles.
class PointsChip extends StatelessWidget {
  const PointsChip({super.key, required this.text, required this.multiplier});

  final String text;
  final bool multiplier;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: multiplier ? FolkGradients.violet : FolkGradients.saffron,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text, maxLines: 1, style: context.folkText.caption.copyWith(color: FolkColors.onGradient, fontWeight: FontWeight.w800)),
    );
  }
}
