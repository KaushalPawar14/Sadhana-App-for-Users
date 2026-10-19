import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';

/// A placeholder for a screen whose contents are still to be specified ("Notes", "History" on the Books screen).
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title, this.icon = Icons.hourglass_empty_rounded});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    return FolkScaffold(
      title: title,
      onBack: () => Navigator.pop(context),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(FolkSpace.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: colors.disabledText),
              const SizedBox(height: FolkSpace.lg),
              Text('Coming soon', key: const ValueKey('coming-soon'), style: text.topBarTitle, textAlign: TextAlign.center),
              const SizedBox(height: FolkSpace.sm),
              Text('This page is on its way.', style: text.small, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
