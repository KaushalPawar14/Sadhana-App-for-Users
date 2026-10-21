import 'package:flutter/material.dart';

/// THE dot of the app: every "new content" indicator (Journey tab and cards, Insights, Leaderboard, Results, Monthly,
/// RDUA Friends, the AI button, Expeditions, Books ...) is green with a thin, crisp dark border (the app's ink,
/// `FolkColors.onGradient`), so it stands out on light and dark surfaces alike. One shared style, no other colour.
/// (The Guide app keeps its own orange dot.)
const Color kUnseenDotFill = Color(0xFF2FBF71);
const Color kUnseenDotBorder = Color(0xFF1E1B2E);

class UnseenDot extends StatelessWidget {
  final double size;
  const UnseenDot({super.key, this.size = 9});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: kUnseenDotFill,
        shape: BoxShape.circle,
        border: Border.all(color: kUnseenDotBorder, width: 1.2),
      ),
    );
  }
}

/// Wraps [child] with an [UnseenDot] pinned to its top-right corner when
/// [show] is true.
///
/// ⚠️ **Two layout modes, and BOTH are needed — 2026-09-11.** Mirrors the
/// Guide app's own `utils/UnseenDot.dart` fix exactly; see that copy's
/// doc comment for the full mechanism. In short:
///
///  * A bounded/tight parent whose child has no explicit size (a grid
///    cell) needs [fillParent] `true` — [Positioned.fill] forces `child`
///    to fill the Stack's resolved size regardless of its own intrinsic
///    size.
///  * An UNCONSTRAINED parent — this is exactly the floating assistant
///    button's own situation: `FloatingAssistantOverlay`'s `Positioned`
///    sets only `left`/`top` (no `width`/`height`), so everything below
///    it gets loose, effectively unbounded constraints — needs
///    [fillParent] `false` (the default): `child` stays a plain,
///    non-positioned `Stack` child, so the Stack sizes itself FROM
///    `child`'s own explicit 58x58 size, rather than trying (and, under
///    an unbounded parent, failing) to size itself first. The
///    unconditional `Positioned.fill` this replaces is the exact,
///    confirmed cause of the disappearing-icon bug: with zero
///    non-positioned children left, `RenderStack` fell back to
///    `constraints.biggest`, which is infinite under this button's own
///    unconstrained parent — `Stack` asserts against exactly that
///    ("A Stack requires bounded constraints from its parent"), failing
///    layout on every single frame, silently, for as long as the dot
///    had anything to show.
///
/// Every existing call site was re-checked against this exact contract:
/// only the Guide app's grid tiles need `fillParent: true`. Every
/// consumer in this app — this button, the nav bar icon, the "RDUA
/// Friends" icon, and every journey-card avatar — keeps the default
/// `false`, since each already has (or resolves to) an explicit,
/// finite size of its own.
class UnseenBadge extends StatelessWidget {
  final Widget child;
  final bool show;
  final double dotSize;
  final Offset offset;

  /// `true` only when the parent gives TIGHT, bounded constraints and
  /// [child] has no explicit size of its own to fall back on (a grid
  /// cell) — not used anywhere in this app today, kept for parity with
  /// the Guide app's copy of this same widget.
  final bool fillParent;

  const UnseenBadge({
    super.key,
    required this.child,
    required this.show,
    this.dotSize = 9,
    this.offset = const Offset(2, -2),
    this.fillParent = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        fillParent ? Positioned.fill(child: child) : child,
        Positioned(
          top: offset.dy,
          right: offset.dx,
          child: UnseenDot(size: dotSize),
        ),
      ],
    );
  }
}
