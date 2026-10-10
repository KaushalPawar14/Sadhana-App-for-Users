import 'package:flutter/material.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import 'PressScale.dart';

// The Profile "Log Out" button: filled red (`FolkColors.logoutRed`, the same in
// light and dark), white label and icon (white on #C62828 is 5.62:1). At least
// 56 dp tall; it grows with the text size.
class LogoutButton extends StatelessWidget {
  const LogoutButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    final radius = BorderRadius.circular(FolkShape.buttonRadius);
    return PressScale(
      child: Container(
        constraints: const BoxConstraints(minHeight: FolkShape.buttonHeight),
        width: double.infinity,
        decoration: BoxDecoration(
          color: FolkColors.logoutRed,
          borderRadius: radius,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.logout_rounded,
                      size: 20, color: FolkColors.onLogoutRed),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "Log Out",
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.button.copyWith(color: FolkColors.onLogoutRed),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
