import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';

// A section divider: a thin line broken in the middle by an upper-case label
// ("ABCDE", "MODULES"). The line is the primary text colour (ink in light,
// cream in dark) and fades softly toward its outer ends. It spans exactly the
// width it is given, so inside a page's padding it ends at the content edges,
// and it keeps equal space above and below.
class SectionDivider extends StatelessWidget {
  const SectionDivider({
    super.key,
    required this.label,
    this.verticalSpace = 26,
  });

  final String label;
  final double verticalSpace;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    Widget line({required bool fadeLeft}) {
      final strong = colors.text.withValues(alpha: .6);
      final faded = colors.text.withValues(alpha: 0);
      return Expanded(
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: fadeLeft ? [faded, strong] : [strong, faded],
            ),
          ),
        ),
      );
    }

    return Semantics(
      header: true,
      label: label,
      excludeSemantics: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: verticalSpace),
        child: Row(
          children: [
            line(fadeLeft: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(label.toUpperCase(), style: text.sectionLabel),
            ),
            line(fadeLeft: false),
          ],
        ),
      ),
    );
  }
}
