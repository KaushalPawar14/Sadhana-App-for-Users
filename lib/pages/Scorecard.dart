import 'package:flutter/material.dart';
import 'package:folk_app/scores/BhagavatamClass.dart';
import 'package:folk_app/scores/BookReading.dart';
import 'package:folk_app/scores/Chanting.dart';
import 'package:folk_app/scores/DailyServices.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/SameGender.dart';
import 'package:folk_app/widgets/EntryAnimation.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/Group2Widgets.dart';
import 'package:folk_app/widgets/ScoreWidgets.dart';

class ScorecardPage extends StatefulWidget {
  ScorecardPage();

  @override
  State<ScorecardPage> createState() => ScorecardState();
}

class ScorecardState extends State<ScorecardPage> {
  // Daily Services is part of the FOLK form only; Hostel and Localite students do
  // not report it, so they do not see that board.
  bool _showDailyServices = true;

  @override
  void initState() {
    super.initState();
    GenderDirectory.forCurrentUser().then((d) {
      if (mounted && d.isHostelLocalite) {
        setState(() => _showDailyServices = false);
      }
    }).catchError((Object _) {});
  }

  final List<Map<String, dynamic>> _allCards = [
    {
      "title": "Chanting",
      "style": FolkGradientStyle.coral,
      "image": "assets/images/Chanting.webp",
      "page": Chanting(),
    },
    {
      "title": "Book Reading",
      "style": FolkGradientStyle.violet,
      "image": "assets/images/BookRead.jpg",
      "page": BookReading(),
    },
    {
      "title": "Bhagavatam Class",
      "style": FolkGradientStyle.violet,
      "image": "assets/images/SBclass.jpg",
      "page": SBclasses(),
    },
    {
      "title": "Daily Services",
      "style": FolkGradientStyle.green,
      "image": "assets/images/Service.jpg",
      "page": DailyServices(),
    },
  ];

  List<Map<String, dynamic>> get cards =>
      [for (final c in _allCards) if (_showDailyServices || c['title'] != 'Daily Services') c];

  Widget buildAnimatedCard(Map<String, dynamic> card, int index) {
    return EntryAnimation(
      index: index,
      child: IdleFloat(
        dy: 4,
        scaleTo: 1.01,
        period: const Duration(seconds: 4),
        child: Padding(
          padding: const EdgeInsets.only(bottom: FolkSpace.cardGap),
          child: ScoreCategoryCard(
            title: card['title'],
            image: card['image'],
            style: card['style'] as FolkGradientStyle,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => card['page']),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FolkScaffold(
      title: "Leaderboard",
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            FolkSpace.pagePadding, FolkSpace.lg, FolkSpace.pagePadding, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List.generate(
            cards.length,
            (index) => buildAnimatedCard(cards[index], index),
          ),
        ),
      ),
    );
  }
}
