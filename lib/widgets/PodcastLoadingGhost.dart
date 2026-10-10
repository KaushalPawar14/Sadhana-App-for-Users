import 'package:flutter/material.dart';

import '../theme/FolkTokens.dart';
import 'GhostPlaceholder.dart';
import 'MinHeightBox.dart';

// What the Podcast screen shows while its episodes load: the "N episodes" line
// and a few episode rows as ghosts, at the sizes and places of the real ones, so
// nothing moves when the data arrives.
//
// Everything in it is as wide as the page allows, never a fixed width that adds
// up to more than a phone is wide. (The earlier loading state had a row of four
// 84 dp language-chip ghosts plus gaps = 360 dp inside 320 dp of room, which
// overflowed by 40 px on a 360 dp phone while the episodes loaded.)
class PodcastLoadingGhost extends StatelessWidget {
  const PodcastLoadingGhost({super.key});

  static const double countLabelHeight = 15.7;
  static const double tileHeight = 72;
  static const int tiles = 5;

  @override
  Widget build(BuildContext context) {
    // Heights follow the student's text size, like the text they stand in for.
    final countHeight = ghostHeight(context, countLabelHeight);
    final textBlock = ghostHeight(context, 39); // title line + duration line
    final rowHeight = tileHeight > 24 + textBlock ? tileHeight : 24 + textBlock;

    return GhostScope(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            FolkSpace.pagePadding, 0, FolkSpace.pagePadding, 0),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: SizedBox(
              height: countHeight,
              child: const Align(
                alignment: Alignment.centerLeft,
                child: GhostPlaceholder(
                    width: 90, height: 10, radius: 6, showBars: false),
              ),
            ),
          ),
          for (var i = 0; i < tiles; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GhostPlaceholder(
                width: double.infinity,
                height: rowHeight,
                radius: FolkShape.tileRadius,
              ),
            ),
        ],
      ),
    );
  }
}
