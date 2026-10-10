import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTypography.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// One tab. [iconBuilder] receives whether the tab is selected and the colour to
// use, so a tab can swap icons. [decorate] wraps the icon from OUTSIDE the
// selected/unselected cross-fade, so anything with its own state or stream
// (the Journey unseen dot) keeps it when the tab is selected or deselected.
class FolkNavItem {
  const FolkNavItem({
    required this.label,
    required this.iconBuilder,
    this.decorate,
  });

  final String label;
  final Widget Function(BuildContext context, bool selected, Color color)
      iconBuilder;
  final Widget Function(BuildContext context, Widget icon)? decorate;
}

// The floating pill navigation: 68 dp tall, 20 dp from the sides and bottom,
// four tabs; the active tab grows to show its icon and label.
class FloatingPillNavBar extends StatelessWidget {
  const FloatingPillNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  }) : assert(items.length >= 2);

  final List<FolkNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  // Space a screen must leave at its bottom so content clears the bar.
  static double reservedHeight(BuildContext context) =>
      FolkShape.navHeight +
      FolkShape.navInset +
      MediaQuery.viewPaddingOf(context).bottom;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        FolkShape.navInset,
        0,
        FolkShape.navInset,
        FolkShape.navInset + bottomInset,
      ),
      // Its own repaint layer: the pill's morph animation repaints only the
      // pill, and the page scrolling behind it does not repaint the pill.
      child: RepaintBoundary(
        child: Container(
          height: FolkShape.navHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(FolkShape.navRadius),
            boxShadow: colors.navShadows,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (var i = 0; i < items.length; i++)
                _NavTab(
                  item: items[i],
                  selected: i == currentIndex,
                  onTap: () => onTap(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final FolkNavItem item;
  final bool selected;
  final VoidCallback onTap;

  // The selected tab's name. It grows with the student's text size up to 1.3x,
  // so four tabs always fit the pill at 360 dp (at 1.6x the pill overflowed).
  Widget _label(FolkTypography text) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: Text(
          item.label,
          style: text.navLabel,
          maxLines: 1,
          softWrap: false,
        ),
      );

  Widget _decorated(BuildContext context, Widget icon) =>
      item.decorate?.call(context, icon) ?? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final duration = FolkMotion.of(context, FolkMotion.navMorph);
    final iconColor = selected ? colors.primaryFg : colors.mutedText;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: AnimatedContainer(
            duration: duration,
            curve: FolkMotion.standard,
            height: FolkShape.touchTarget,
            constraints: const BoxConstraints(minWidth: FolkShape.touchTarget),
            padding: EdgeInsets.symmetric(horizontal: selected ? 18 : 12),
            decoration: BoxDecoration(
              color: selected ? colors.primaryBg : Colors.transparent,
              borderRadius: BorderRadius.circular(FolkShape.touchTarget / 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _decorated(
                  context,
                  AnimatedSwitcher(
                    duration: duration,
                    child: KeyedSubtree(
                      key: ValueKey<bool>(selected),
                      child: item.iconBuilder(context, selected, iconColor),
                    ),
                  ),
                ),
                // AnimatedSize cannot take a zero duration (it would restart its
                // animation inside layout), so with "reduce animations" on the
                // label simply appears.
                if (duration == Duration.zero)
                  if (selected)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: _label(text),
                    )
                  else
                    const SizedBox.shrink()
                else
                  AnimatedSize(
                    duration: duration,
                    curve: FolkMotion.standard,
                    alignment: Alignment.centerLeft,
                    child: selected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: _label(text),
                          )
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
