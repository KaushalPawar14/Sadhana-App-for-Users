import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/ProfileMenuIconTile.dart';

/// Profile -> My Music. Its contents will be specified later; for now a friendly "Coming soon".
class MyMusicPage extends StatelessWidget {
  const MyMusicPage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = context.folkText;
    return FolkScaffold(
      title: 'My Music',
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(FolkSpace.pagePadding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ProfileMenuIconTile(CupertinoIcons.music_note_2),
              const SizedBox(height: FolkSpace.lg),
              Text('Coming soon', key: const ValueKey('my-music-coming-soon'), style: text.topBarTitle, textAlign: TextAlign.center),
              const SizedBox(height: FolkSpace.sm),
              Text("We're preparing something for you here.", style: text.small, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
