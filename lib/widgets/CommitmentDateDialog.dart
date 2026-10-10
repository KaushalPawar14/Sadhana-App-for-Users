import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'FolkDialog.dart';

// The "Set your commitment date" dialog that comes before a book is started.
//
// It returns the chosen date ("yyyy-MM-dd") when the student taps Start Reading,
// and NULL when they close it any other way: Cancel, a tap outside, or the system
// back button. A null answer means nothing was started: the caller writes nothing
// and opens nothing.
Future<String?> showCommitmentDateDialog(
  BuildContext context, {
  required String title,
}) {
  DateTime? picked;

  return showDialog<String>(
    context: context,
    // barrierDismissible defaults to true: a tap outside closes it, and the
    // system back button closes it too (no PopScope blocks it).
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final colors = context.folk;
          final text = context.folkText;
          return FolkDialog.alert(
            context,
            title: "Set your commitment date",
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.bodyStrong),
                const SizedBox(height: 8),
                Text(
                  "Choose a target date to finish this book. You need one "
                  "to start reading.",
                  style: text.small,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () async {
                    final result = await showDatePicker(
                      context: dialogContext,
                      initialDate: picked ?? DateTime.now(),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (result != null) {
                      setDialogState(() => picked = result);
                    }
                  },
                  borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                  child: Container(
                    constraints:
                        const BoxConstraints(minHeight: FolkShape.touchTarget),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: colors.surfaceSecondary,
                      borderRadius: BorderRadius.circular(FolkShape.tileRadius),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today,
                            size: 18, color: colors.mutedText),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Text(
                            picked == null
                                ? "Tap to choose a date"
                                : picked!.toIso8601String().split('T')[0],
                            style:
                                picked == null ? text.small : text.bodyStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                style: FolkDialog.quietButton(colors, text),
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                style: FolkDialog.primaryButton(colors, text),
                onPressed: picked == null
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          picked!.toIso8601String().split('T')[0],
                        ),
                child: const Text("Start Reading"),
              ),
            ],
          );
        },
      );
    },
  );
}
