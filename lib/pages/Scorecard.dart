import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/scores/BhagavatamClass.dart';
import 'package:folk_app/scores/BookReading.dart';
import 'package:folk_app/scores/Chanting.dart';
import 'package:folk_app/scores/DailyServices.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:provider/provider.dart';

class ScorecardPage extends StatefulWidget {
  ScorecardPage();

  @override
  State<ScorecardPage> createState() => ScorecardState();
}

class ScorecardState extends State<ScorecardPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  final List<Map<String, dynamic>> cards = [
    {
      "title": "Chanting",
      "image": "assets/images/Chanting.png",
      "page": Chanting(),
    },
    {
      "title": "Book Reading",
      "image": "assets/images/BookRead.jpg",
      "page": BookReading(),
    },
    {
      "title": "Bhagavatam Class",
      "image": "assets/images/SBclass.jpg",
      "page": SBclasses(),
    },
    {
      "title": "Daily Services",
      "image": "assets/images/Service.jpg",
      "page": DailyServices(),
    },
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget buildAnimatedCard(Map<String, dynamic> card, int index, ColorProvider colorProvider) {
    // Different offsets for each card → "randomized look"
    final offsets = [
      const Offset(0, -20),
      const Offset(20, 0),
      const Offset(-15, 10),
      const Offset(10, -15),
    ];
    final offset = offsets[index % offsets.length];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final double float = 6 * (0.5 - (_controller.value - 0.5).abs());
        return Transform.translate(
          offset: offset * (_controller.value * 0.3) + Offset(0, float),
          child: Transform.scale(
            scale: 0.95 + (_controller.value * 0.05),
            child: GestureDetector(
              onTap: () async {
                final userDoc = await FirebaseFirestore.instance
                    .collection('users')
                    .doc(FirebaseAuth.instance.currentUser!.uid)
                    .get();

                final role = userDoc.data()?['role'] ?? '';

                if (role == 'Stay at Hostel') {
                  showSnackbar(context, "Coming soon !!", Colors.yellow, Icons.watch_later);
                } else {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => card['page']),
                  );
                }
              },

              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      colorProvider.thirdColor,
                      colorProvider.secondColor.withOpacity(0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: colorProvider.secondColor.withOpacity(0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Hero(
                      tag: card['title'],
                      child: CircleAvatar(
                        radius: 42,
                        backgroundImage: AssetImage(card['image']),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      card['title'],
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.only(top: 80, bottom: 50),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List.generate(
                cards.length,
                    (index) => buildAnimatedCard(cards[index], index, colorProvider),
              ),
            ),
          ),
        ),
      );
    });
  }
}
