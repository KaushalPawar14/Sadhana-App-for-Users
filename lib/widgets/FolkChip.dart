import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// A fully rounded option chip. Selected: ink-on-cream (or a gradient style when
// [selectedStyle] is given, as for a chosen language). Unselected: a surface.
// The hit area is always at least 48 dp tall.
class FolkChip extends StatelessWidget {
  const FolkChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedStyle,
    this.icon,
    this.large = false,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final FolkGradientStyle? selectedStyle;
  final IconData? icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final height = large ? FolkShape.chipHeightLarge : FolkShape.chipHeight;
    final radius = BorderRadius.circular(height / 2);

    final useGradient = selected && selectedStyle != null;
    final Color foreground = useGradient
        ? FolkColors.onGradient
        : selected
            ? colors.primaryFg
            : colors.text;

    return Semantics(
      button: true,
      selected: selected,
      child: PressScale(
        enabled: onTap != null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: FolkShape.touchTarget),
          child: Center(
            widthFactor: 1,
            child: Container(
              height: height,
              decoration: BoxDecoration(
                borderRadius: radius,
                gradient: useGradient ? FolkGradients.of(selectedStyle!) : null,
                color: useGradient
                    ? null
                    : selected
                        ? colors.primaryBg
                        : colors.surface,
              ),
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (icon != null) ...[
                          Icon(icon, size: 18, color: foreground),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          label,
                          style: text.chip.copyWith(color: foreground),
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
