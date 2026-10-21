import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../theme/FolkTypography.dart';

// Shared look for the app's dialogs, so every AlertDialog is the same surface,
// radius 28, with 48 dp buttons. Wording and behaviour stay with the caller.
abstract final class FolkDialog {
  static RoundedRectangleBorder shape() => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(FolkShape.cardRadius),
      );

  // A quiet button (Cancel / No).
  static ButtonStyle quietButton(FolkColors colors, FolkTypography text) =>
      TextButton.styleFrom(
        minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
        foregroundColor: colors.mutedText,
        textStyle: text.chip,
      );

  // A destructive quiet button (Delete / Reset).
  static ButtonStyle dangerButton(FolkColors colors, FolkTypography text) =>
      TextButton.styleFrom(
        minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
        foregroundColor: colors.calendarMissedText,
        textStyle: text.chip,
      );

  // The main button (Save / Yes / OK): ink on cream, a stadium.
  static ButtonStyle primaryButton(FolkColors colors, FolkTypography text) =>
      ElevatedButton.styleFrom(
        minimumSize: const Size(FolkShape.touchTarget, FolkShape.touchTarget),
        backgroundColor: colors.primaryBg,
        foregroundColor: colors.primaryFg,
        elevation: 0,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        textStyle: text.button,
      );

  // An input field that sits inside a dialog or sheet: filled, no outline.
  static InputDecoration field(BuildContext context, {String? label, String? hint}) {
    final colors = context.folk;
    final text = context.folkText;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: text.small,
      hintStyle: text.body.copyWith(color: colors.mutedText),
      filled: true,
      fillColor: colors.surfaceSecondary,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FolkShape.tileRadius),
        borderSide: BorderSide.none,
      ),
    );
  }

  // A themed AlertDialog.
  static AlertDialog alert(
    BuildContext context, {
    Key? key,
    required String title,
    Widget? content,
    List<Widget> actions = const [],
    bool scrollable = false,
  }) {
    final colors = context.folk;
    final text = context.folkText;
    return AlertDialog(
      key: key,
      scrollable: scrollable,
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shape: shape(),
      title: Text(title, style: text.topBarTitle),
      content: content,
      actions: actions,
    );
  }
}
