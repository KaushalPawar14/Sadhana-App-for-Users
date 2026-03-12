import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:iconly/iconly.dart';
import 'package:provider/provider.dart';
import 'package:sizer/sizer.dart';

import '../utils/MalaLoading.dart';

class DailyServices extends StatelessWidget {
  // Fetch leaderboard data
  Future<List<Map<String, dynamic>>> fetchLeaderboard() async {
    var userDocs =
    await FirebaseFirestore.instance.collection('scorecard').get();

    List<Map<String, dynamic>> leaderboard = [];
    for (var userDoc in userDocs.docs) {
      if(userDoc.id == 'flag') continue;
      leaderboard.add({
        'userName': userDoc.id,
        'totalServiceDone': userDoc['totalServiceDone'] ?? 0,
      });
    }

    leaderboard
        .sort((a, b) => b['totalServiceDone'].compareTo(a['totalServiceDone']));
    return leaderboard;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(65),
          child: AppBar(
            elevation: 0,
            backgroundColor: colorProvider.color,
            leading: IconButton(
              icon: Icon(
                IconlyBroken.arrow_left,
                size: 3.6.h,
                color: colorProvider.secondColor,
              ),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Service Leaderboard',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorProvider.secondColor,
                fontSize: 18.sp,
              ),
            ),
          ),
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: fetchLeaderboard(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CustomLoader();
            }

            if (snapshot.hasError) {
              return Center(
                  child: Text('Error: ${snapshot.error}',
                      style: TextStyle(color: colorProvider.secondColor)));
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                  child: Text(
                    'No leaderboard data available.',
                    style: TextStyle(
                        color: colorProvider.secondColor, fontSize: 12.sp),
                  ));
            }

            List<Map<String, dynamic>> leaderboard = snapshot.data!;

            return ListView.builder(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              itemCount: leaderboard.length,
              itemBuilder: (context, index) {
                var user = leaderboard[index];

                // Rank styles
                Color rankColor;
                if (index == 0) {
                  rankColor = Colors.amber.shade700;
                } else if (index == 1) {
                  rankColor = Colors.grey.shade400;
                } else if (index == 2) {
                  rankColor = Colors.brown.shade400;
                } else {
                  rankColor = colorProvider.thirdColor.withOpacity(0.7);
                }

                return TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: Duration(milliseconds: 600 + (index * 120)),
                  curve: Curves.easeOutBack,
                  builder: (context, value, child) {
                    return Transform.translate(
                      offset: Offset(0, (1 - value) * 40),
                      child: Opacity(
                        opacity: value.clamp(0.0, 1.0),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Card(
                      elevation: 8,
                      shadowColor: rankColor.withOpacity(0.6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          gradient: LinearGradient(
                            colors: [
                              rankColor.withOpacity(0.9),
                              colorProvider.secondColor.withOpacity(0.8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 18, horizontal: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.white.withOpacity(0.25),
                                child: Text(
                                  (index + 1).toString(),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    fontSize: 16.sp,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    user['userName'],
                                    overflow: TextOverflow.visible,
                                    softWrap: true,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: colorProvider.color,
                                      fontSize: 15.sp,
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                "${user['totalServiceDone']} pts",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  color: colorProvider.color,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    });
  }
}
