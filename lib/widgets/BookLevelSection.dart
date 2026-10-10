import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkCard.dart';

// One level of the Books list: a card with a header that opens and closes. It
// starts CLOSED. The book cards are built only while it is open (and while it is
// closing); a closed section builds none of them.
class BookLevelSection extends StatefulWidget {
  const BookLevelSection({
    super.key,
    required this.title,
    this.subtitle,
    required this.bodyBuilder,
    this.initiallyOpen = false,
  });

  final String title;
  // Optional second line (a count).
  final String? subtitle;

  // Builds the section's contents. Called only while the section is open.
  final WidgetBuilder bodyBuilder;
  final bool initiallyOpen;

  @override
  State<BookLevelSection> createState() => _BookLevelSectionState();
}

class _BookLevelSectionState extends State<BookLevelSection>
    with SingleTickerProviderStateMixin {
  static const Duration _duration = Duration(milliseconds: 260);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _duration,
    value: widget.initiallyOpen ? 1 : 0,
  );
  late final Animation<double> _curve =
      CurvedAnimation(parent: _controller, curve: FolkMotion.standard);
  late bool _open = widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    // Once the closing animation has finished, the contents are dropped.
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = FolkMotion.of(context, _duration);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    // With "reduce animations" the duration is zero and the status listener
    // above has already run; make sure the closed state is drawn.
    if (_controller.duration == Duration.zero) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    final showBody = _open || !_controller.isDismissed;

    return FolkCard(
      margin: const EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            expanded: _open,
            label: widget.subtitle == null
                ? widget.title
                : '${widget.title}, ${widget.subtitle}',
            excludeSemantics: true,
            onTap: _toggle,
            child: InkWell(
              onTap: _toggle,
              borderRadius: BorderRadius.circular(FolkShape.cardRadius),
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(minHeight: FolkShape.touchTarget),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(widget.title, style: text.topBarTitle),
                            if (widget.subtitle != null)
                              Text(widget.subtitle!, style: text.caption),
                          ],
                        ),
                      ),
                      RotationTransition(
                        turns: Tween<double>(begin: 0, end: .5).animate(_curve),
                        child: Icon(Icons.expand_more, color: colors.text),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (showBody)
            ClipRect(
              child: SizeTransition(
                sizeFactor: _curve,
                axisAlignment: -1,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                  child: widget.bodyBuilder(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
