import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/scores/BhagavatamClass.dart';
import 'package:folk_app/scores/BookReading.dart';
import 'package:folk_app/scores/Chanting.dart';
import 'package:folk_app/scores/DailyServices.dart';
import 'package:folk_app/theme/FolkTokens.dart';
import 'package:folk_app/utils/Snackbar.dart';
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
  final List<Map<String, dynamic>> cards = [
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
            onTap: () async {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(FirebaseAuth.instance.currentUser!.uid)
                  .get();

              final role = userDoc.data()?['role'] ?? '';

              // Localites (Master Task, 2026-09-03) are gated exactly like
              // Hostel residents here.
              if (role == 'Stay at Hostel' || role == 'Stay at Localite') {
                showSnackbar(context, "Coming soon !!", Colors.yellow, Icons.watch_later);
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => card['page']),
                );
              }
            },
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
