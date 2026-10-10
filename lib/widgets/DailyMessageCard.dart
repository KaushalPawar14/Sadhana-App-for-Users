import 'package:flutter/material.dart';

import '../services/DailyMessageService.dart';
import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkTypography.dart';
import 'MinHeightBox.dart' show ghostHeight;
import '../utils/SimpleMarkdown.dart' show markdownToPlain;
import 'MarkdownText.dart';
import 'PressScale.dart';
import 'TypingDots.dart';

// The warm "TODAY'S MESSAGE" card. Ask draws it inside the chat; Journey draws
// the same card at the top of the screen. With [onTap] it is a button; with
// [maxLines] longer text is cut with an ellipsis; with [loading] the text is
// replaced by "Loading" and three animated dots.
class DailyMessageCard extends StatelessWidget {
  const DailyMessageCard({
    super.key,
    required this.text,
    this.maxLines,
    this.onTap,
    this.minHeight = 0,
    this.loading = false,
  });

  final String text;
  final int? maxLines;
  final VoidCallback? onTap;
  final double minHeight;
  final bool loading;

  Widget _loadingBody(FolkTypography style) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Loading',
            style: style.messageText.copyWith(fontSize: 18, height: 1.38),
          ),
          const SizedBox(width: 10),
          const TypingDots(color: FolkColors.onGradientSecondary),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final style = context.folkText;
    final radius = BorderRadius.circular(FolkShape.cardRadius);
    final content = Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wb_sunny_outlined,
                  size: 14, color: FolkColors.onGradientSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  "Today's message".toUpperCase(),
                  style: style.label
                      .copyWith(color: FolkColors.onGradientSecondary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: FolkMotion.of(context, FolkMotion.ghostCrossFade),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.topLeft,
              children: [...previous, if (current != null) current],
            ),
            child: loading
                ? KeyedSubtree(
                    key: const ValueKey<String>('loading'),
                    child: _loadingBody(style),
                  )
                : KeyedSubtree(
                    key: ValueKey<String>('text:$text'),
                    // The message is the assistant's: its simple markdown is
                    // shown properly. With a line limit (Journey) it stays one
                    // paragraph that ends in an ellipsis.
                    child: MarkdownText(
                      text,
                      maxLines: maxLines,
                      overflow: maxLines == null ? null : TextOverflow.ellipsis,
                      style: style.messageText
                          .copyWith(fontSize: 18, height: 1.38),
                    ),
                  ),
          ),
        ],
      ),
    );

    Widget card = Container(
      width: double.infinity,
      constraints: BoxConstraints(minHeight: minHeight),
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        gradient: FolkGradients.sky,
        borderRadius: radius,
      ),
      child: onTap == null
          ? content
          : Material(
              type: MaterialType.transparency,
              borderRadius: radius,
              clipBehavior: Clip.antiAlias,
              child: InkWell(onTap: onTap, borderRadius: radius, child: content),
            ),
    );

    if (onTap != null) {
      card = Semantics(
        button: true,
        container: true,
        label: loading
            ? "Today's message. Loading"
            : "Today's message. ${markdownToPlain(text)}",
        excludeSemantics: true,
        child: PressScale(child: card),
      );
    }
    return card;
  }
}

// Today's message at the top of Journey. Same card, same colour, same size in
// every state; the heading "TODAY'S MESSAGE" is always there.
//
//  - generating / being read -> "Loading" and three animated dots (no ghost)
//  - ready                   -> the text (at most four lines), cross-faded in
//  - disclosure not accepted -> the "tap to open" line
//  - failed                  -> the "tap to open" line; it is tried again the
//                               next time the app is opened
//
// A message cached on this device for today is "ready" from the first frame.
// Tapping the card in any state opens Ask.
//
// The card is [minHeightFor] tall (room for the four-line maximum at the
// student's text size) and a message is cut at four lines, so it is the same
// height in every state and nothing moves when the message arrives.
class JourneyTodayMessage extends StatelessWidget {
  const JourneyTodayMessage({
    super.key,
    required this.state,
    required this.onTap,
  });

  final DailyMessageState state;
  final VoidCallback onTap;

  static const String waitingText =
      "Your message for today is waiting — tap to open";

  static double minHeightFor(BuildContext context) =>
      36 + ghostHeight(context, 16) + 8 + 4 * ghostHeight(context, 24.84);

  @override
  Widget build(BuildContext context) {
    final text = (state.text ?? '').trim();
    final loading = state.status == DailyMessageStatus.loading;
    final ready = state.status == DailyMessageStatus.ready && text.isNotEmpty;
    return DailyMessageCard(
      text: ready ? text : waitingText,
      loading: loading,
      maxLines: 4,
      minHeight: minHeightFor(context),
      onTap: onTap,
    );
  }
}
