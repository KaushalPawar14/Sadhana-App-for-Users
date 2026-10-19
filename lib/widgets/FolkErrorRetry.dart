import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PrimaryButton.dart';

// What a screen shows when its data could not be read: one friendly line and a Retry
// button. It never shows the technical error (a raw Firestore message such as
// "[cloud_firestore/permission-denied] ..." means nothing to a student and looks broken).
//
// [onRetry] must make the screen read its data again: for a builder whose stream or future
// is created in `build`, a `setState(() {})` is enough; for one kept in a field, create the
// stream again first.
class FolkErrorRetry extends StatelessWidget {
  const FolkErrorRetry({
    super.key,
    required this.onRetry,
    this.message = "Couldn't load this just now.",
    this.compact = false,
  });

  final VoidCallback onRetry;

  // The friendly line, e.g. "Couldn't load your calendar just now.".
  final String message;

  // True inside a card or a list, where there is little room.
  final bool compact;

  // The one line every screen shows when it cannot say anything better.
  static const String hint = 'Check your connection and try again.';

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: FolkSpace.pagePadding,
            vertical: compact ? FolkSpace.lg : FolkSpace.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!compact) ...[
              Icon(Icons.cloud_off_rounded, size: 44, color: colors.mutedText),
              const SizedBox(height: FolkSpace.md),
            ],
            Text(message, textAlign: TextAlign.center, style: text.body),
            const SizedBox(height: FolkSpace.xs),
            Text(hint, textAlign: TextAlign.center, style: text.small),
            const SizedBox(height: FolkSpace.lg),
            PrimaryButton(label: 'Retry', onPressed: onRetry, expanded: false),
          ],
        ),
      ),
    );
  }
}

// Gives a screen part a way to run its builder again. For a stateless screen whose
// FutureBuilder creates its future inside `build`, wrapping it in this makes Retry work:
// `FolkRetryScope(builder: (context, retry) => FutureBuilder(...onRetry: retry...))`.
class FolkRetryScope extends StatefulWidget {
  const FolkRetryScope({super.key, required this.builder});

  final Widget Function(BuildContext context, VoidCallback retry) builder;

  @override
  State<FolkRetryScope> createState() => _FolkRetryScopeState();
}

class _FolkRetryScopeState extends State<FolkRetryScope> {
  void _retry() => setState(() {});

  @override
  Widget build(BuildContext context) => widget.builder(context, _retry);
}
