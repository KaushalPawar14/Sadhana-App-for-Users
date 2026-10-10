import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/FolkColors.dart';
import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/FolkStatusBar.dart';
import '../widgets/PrimaryButton.dart';

/// Blocking "please update" screen — follow-up task, 2026-09-10.
///
/// Reached only from `pages/SplashScreen.dart`, `pushReplacement`d in
/// place of the normal destination (`AnimatedLogin`) when `utils/
/// ForceUpdateCheck.isUpdateRequired()` returns true. Because
/// `AnimatedLogin` is never built in that branch, `markAppReady()` (called
/// from ITS OWN `initState()`) never runs either — a queued notification
/// route structurally cannot fire while this screen is up; there is
/// nothing that would ever flush it.
///
/// `PopScope<Object?>(canPop: false, ...)` is the exact idiom already used
/// throughout this app (see `pages/Welcome.dart`'s own header comment for
/// the established pattern) — but unlike every existing use of it (close
/// the keyboard first, THEN allow a normal pop/exit), this one absorbs a
/// back press completely: no text field lives here, and there is no
/// "then let them through" fallback, because letting them through is
/// exactly what this screen exists to prevent until they update.
class ForceUpdateScreen extends StatelessWidget {
  static const String playStoreUrl =
      'https://play.google.com/store/apps/details?id=org.folksurat.students';

  const ForceUpdateScreen({super.key});

  Future<void> _openPlayStore(BuildContext context) async {
    final uri = Uri.parse(playStoreUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open the Play Store. Please update manually."),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // Absorbed, deliberately — see this class's own doc comment.
      },
      child: FolkStatusBar(
        child: Scaffold(
          backgroundColor: colors.pageBackground,
          body: FolkPageBackground(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 104,
                        height: 104,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: FolkGradients.violet,
                        ),
                        child: const Icon(Icons.system_update_alt,
                            size: 52, color: FolkColors.onGradient),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Update required",
                        style: text.screenTitle.copyWith(fontSize: 28),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        "A newer version of the FOLK app is required to continue. "
                        "Please update from the Play Store to keep using the app.",
                        textAlign: TextAlign.center,
                        style: text.body.copyWith(height: 1.5),
                      ),
                      const SizedBox(height: 28),
                      PrimaryButton(
                        label: "Update now",
                        icon: Icons.shop,
                        onPressed: () => _openPlayStore(context),
                      ),
                    ],
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
