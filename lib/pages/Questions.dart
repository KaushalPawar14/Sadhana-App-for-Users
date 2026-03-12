import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/services/SendNotifications.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/SadhanaReports.dart';
import '../services/CompetitionService.dart';
import '../services/ScorecardUpdate.dart';

class QuestionsPage extends StatefulWidget {
  @override
  State<QuestionsPage> createState() => _QuestionsPageState();
}

class _QuestionsPageState extends State<QuestionsPage> {
  TextEditingController dateController = TextEditingController();
  TextEditingController roundsController = TextEditingController();
  TextEditingController bookController = TextEditingController();
  TextEditingController templeEntered = TextEditingController();
  TextEditingController academicsStudy = TextEditingController();
  TextEditingController sleepTime = TextEditingController();
  TextEditingController japaFinish = TextEditingController();

  Map<int, int?> selectedOptions = {};
  Map<int, String> answers = {};

  void submitQuiz() async {
    FocusScope.of(context).requestFocus(FocusNode());

    // Fill answers from controllers
    answers[0] = templeEntered.text;
    answers[4] = dateController.text;
    answers[5] = roundsController.text;
    answers[6] = bookController.text;
    answers[7] = japaFinish.text;
    answers[8] = sleepTime.text;

    // ======= VALIDATION: CHECK ALL FIELDS BEFORE SUBMITTING =======
    bool allFilled = templeEntered.text.isNotEmpty &&
        dateController.text.isNotEmpty &&
        roundsController.text.isNotEmpty &&
        bookController.text.isNotEmpty &&
        academicsStudy.text.isNotEmpty &&
        sleepTime.text.isNotEmpty &&
        japaFinish.text.isNotEmpty &&
        selectedOptions.containsKey(2) && // SB Class
        selectedOptions.containsKey(3) && // Daily Services
        selectedOptions.containsKey(9); // Extra lecture

    if (!allFilled) {
      showSnackbar(context, 'Please fill all the fields!', Colors.black45,
          CupertinoIcons.info);
      return;
    }

    print(answers);

    String? Rounds = answers[5];
    String? bookRead = answers[6];
    String? Hearing = answers[2];
    String? serviceDone = answers[3];
    String? timeEntered = answers[0];
    String? japaEnd = answers[7];
    String reversedDate = reverseDateFormat(answers[4]!);
    String? Sleeping = answers[8];

    TimeOfDay parsedTempleEntry = _parseTime(timeEntered!);
    TimeOfDay parsedFinishTiming = _parseTime(japaEnd!);
    TimeOfDay parsedSleepingTiming = _parseTime(Sleeping!);

    String sentence = "";
    final double extraLecturePoints;

    if (answers[9] == 'more than 30 mins') {
      extraLecturePoints =2;
      sentence =
          "📿: $Rounds rounds,  📖 : $bookRead mins\n👂👍>30mins : $Hearing points ,  🙇🏻‍♂️ : $japaEnd";
    } else if (answers[9] == 'more than 15 mins') {
      extraLecturePoints = 1;
      sentence =
          "📿: $Rounds rounds,  📖 : $bookRead mins\n👂👍>15mins : $Hearing points ,  🙇🏻‍♂️ : $japaEnd";
    } else {
      extraLecturePoints = 0;
      sentence =
          "📿: $Rounds rounds,  📖 : $bookRead mins\n👂👎 : $Hearing points ,  🙇🏻‍♂️ : $japaEnd";
    }

    print(sentence);
    showSnackbar(context, 'Sadhana submitted successfully',
        CupertinoColors.activeGreen, Icons.done_outline_rounded);

    setState(() {
      answers.clear();
      dateController.clear();
      bookController.clear();
      roundsController.clear();
      academicsStudy.clear();
      // sleepHours.clear();
      sleepTime.clear();
      japaFinish.clear();
      templeEntered.clear();
      selectedOptions.clear();
    });

    // sendNotificationToAdmin(reversedDate, timeEntered, Sleeping, sentence);
    print(
        'Report Data: $reversedDate, $timeEntered, $Rounds, $bookRead, $Hearing, ${serviceDone}, $japaEnd');

    SadhanaReport newReport = SadhanaReport(
        templeEntry: parsedTempleEntry,
        chantRounds: int.parse(Rounds!),
        bookReading: int.parse(bookRead!),
        classHearing: int.parse(Hearing!),
        dailyServices: int.parse(serviceDone!),
        finishTiming: parsedFinishTiming,
        sleepTiming: parsedSleepingTiming);
    print('New Report created: ${newReport.toMap()}');

    await saveSadhanaReport(newReport, reversedDate, extraLecturePoints);

  }

  Future<void> SelectDate() async {
    DateTime? pickedDate = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime.now());
    if (pickedDate != null) {
      setState(() {
        dateController.text = pickedDate.toString().split(" ")[0];
      });
    }
  }

  TimeOfDay _parseTime(String timeString) {
    final formats = [
      DateFormat("HH:mm"), // 24-hour, e.g. 20:00
      DateFormat("H:mm"), // 24-hour, single-digit hour e.g. 9:05
      DateFormat("h:mm a"), // 12-hour with AM/PM, e.g. 8:00 PM
    ];

    for (final format in formats) {
      try {
        final dt = format.parse(timeString);
        return TimeOfDay(
            hour: dt.hour, minute: dt.minute); // ✅ always normalized
      } catch (_) {}
    }

    print("❌ Invalid time format: $timeString");
    return TimeOfDay(hour: 0, minute: 0);
  }

  String reverseDateFormat(String date) {
    try {
      DateTime parsedDate = DateTime.parse(date);
      String formattedDate = DateFormat('dd-MM-yyyy').format(parsedDate);
      return formattedDate;
    } catch (e) {
      print('Error in date conversion: $e');
      return date;
    }
  }
  
  BoxDecoration glassDecoration(ColorProvider colorProvider) {
    return BoxDecoration(
      color: colorProvider.fourthColor.withOpacity(0.65),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color: colorProvider.secondColor.withOpacity(0.15),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.08),
          blurRadius: 20,
          offset: Offset(0, 8),
        )
      ],
    );
  }

  BoxDecoration modernCard(ColorProvider colorProvider) {
    return BoxDecoration(
      color: colorProvider.fourthColor,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: colorProvider.secondColor.withOpacity(0.08),
        width: 1,
      ),
    );
  }

  Widget questionTitle(String text, ColorProvider colorProvider) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: colorProvider.secondColor,
        letterSpacing: 0.2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: SafeArea(
          child: SingleChildScrollView(
            physics: BouncingScrollPhysics(),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  SizedBox(height: 35),
                  buildQuestionTextField(
                      question: "Date of Submission",
                      controller: dateController,
                      labelText: "Enter Date",
                      keyboardType: TextInputType.none,
                      onTap: () {
                        SelectDate();
                      }),
                  const SizedBox(height: 20),
                  buildQuestionTimePicker(
                      question: "Time Entered Temple Hall",
                      controller: templeEntered,
                      labelText: "HH : MM",
                      context: context),
                  const SizedBox(height: 20),
                  buildQuestionDropdown(
                    question: "SB Class - 7:20 AM to 7:55 AM",
                    questionId: 2,
                    optionsMap: {
                      "2": "Fully",
                      "1": "Partial",
                      "0": "Missed",
                    },
                  ),
                  const SizedBox(height: 20),
                  buildQuestionTextField(
                      question: "Total Academics Study yesterday",
                      controller: academicsStudy,
                      labelText: "in mins",
                      keyboardType: TextInputType.number),
                  const SizedBox(height: 20),
                  buildQuestionDropdown(
                    question: "Daily Assigned Services",
                    questionId: 3,
                    optionsMap: {
                      "2": "Done fully",
                      "1": "Done partially",
                      "0": "Not done",
                    },
                  ),
                  const SizedBox(height: 20),
                  buildQuestionTextField(
                    question: "Total rounds chanted yesterday",
                    controller: roundsController,
                    labelText: "Total rounds",
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  buildQuestionTextField(
                    question: "Total book reading (in mins) yesterday",
                    controller: bookController,
                    labelText: "Total reading",
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 20),
                  buildQuestionTimePicker(
                      question: "Sleep time of yesterday",
                      controller: sleepTime,
                      labelText: "HH : MM",
                      context: context),
                  const SizedBox(height: 20),
                  buildQuestionTimePicker(
                      question: "Japa finish time of yesterday",
                      controller: japaFinish,
                      labelText: "HH : MM",
                      context: context),
                  const SizedBox(height: 20),
                  buildQuestionCard(
                    question: "Heard extra lecture yesterday ?",
                    questionId: 9,
                    numberOfOptions: 3,
                    options: ["more than 30 mins", "more than 15 mins", "No"],
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 30, vertical: 15),
                    ),
                    onPressed: () async {
                      bool internet = await hasInternet();
                      if (!internet) {
                        showSnackbar(
                            context,
                            "Please turn on your internet !!",
                            Colors.orange,
                            Icons
                                .signal_cellular_connected_no_internet_4_bar_outlined);
                        return;
                      }
                      submitQuiz();
                    },
                    child: Text(
                      "Submit",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget buildQuestionCard({
    required String question,
    required int questionId,
    required int numberOfOptions,
    required List<String> options,
    String? text,
  }) {
    if (options.length != numberOfOptions) {
      throw Exception("Number of options does not match");
    }

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Container(
        decoration: modernCard(colorProvider),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            questionTitle(question, colorProvider),
            const SizedBox(height: 14),

            for (int i = 0; i < options.length; i++)
              GestureDetector(
                onTap: () {
                  setState(() {
                    selectedOptions[questionId] = i;
                    answers[questionId] = options[i];
                  });
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selectedOptions[questionId] == i
                          ? colorProvider.secondColor
                          : colorProvider.secondColor.withOpacity(0.15),
                    ),
                    color: selectedOptions[questionId] == i
                        ? colorProvider.secondColor.withOpacity(0.06)
                        : Colors.transparent,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        selectedOptions[questionId] == i
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        size: 18,
                        color: selectedOptions[questionId] == i
                            ? colorProvider.secondColor
                            : colorProvider.secondColor.withOpacity(0.5),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          options[i],
                          style: TextStyle(
                            fontSize: 14,
                            color: colorProvider.secondColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (text != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorProvider.secondColor.withOpacity(0.6),
                  ),
                ),
              )
          ],
        ),
      );
    });
  }

  Widget buildQuestionDropdown({
    required String question,
    required int questionId,
    required Map<String, String> optionsMap,
  }) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Container(
        decoration: modernCard(colorProvider),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            questionTitle(question, colorProvider),
            const SizedBox(height: 12),

            DropdownButtonFormField<String>(
              value: answers[questionId],
              dropdownColor: colorProvider.fourthColor,

              style: TextStyle(color: colorProvider.secondColor),

              decoration: InputDecoration(
                filled: true,
                fillColor: colorProvider.color.withOpacity(0.25),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),

              items: optionsMap.entries.map((entry) {
                return DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(
                    "${entry.key} - ${entry.value}",
                    style: TextStyle(color: colorProvider.secondColor),
                  ),
                );
              }).toList(),

              onChanged: (value) {
                setState(() {
                  answers[questionId] = value!;
                  selectedOptions[questionId] = int.parse(value);
                });
              },
            ),
          ],
        ),
      );
    });
  }

  Widget buildQuestionTextField({
    required String question,
    required TextEditingController controller,
    required String labelText,
    required TextInputType keyboardType,
    Function()? onTap,
  }) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Container(
        decoration: modernCard(colorProvider),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            questionTitle(question, colorProvider),
            const SizedBox(height: 12),

            TextField(
              controller: controller,
              keyboardType: keyboardType,
              onTap: onTap,
              style: TextStyle(color: colorProvider.secondColor),

              decoration: InputDecoration(
                filled: true,
                fillColor: colorProvider.color.withOpacity(0.25),
                hintText: labelText,
                hintStyle: TextStyle(
                    color: colorProvider.secondColor.withOpacity(0.5)),
                contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),

                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget buildQuestionTimePicker({
    required String question,
    required TextEditingController controller,
    required String labelText,
    required BuildContext context,
  }) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Container(
        decoration: modernCard(colorProvider),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            questionTitle(question, colorProvider),
            const SizedBox(height: 12),

            GestureDetector(
              onTap: () async {
                final TimeOfDay? pickedTime = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );

                if (pickedTime != null) {
                  final now = DateTime.now();
                  final dt = DateTime(
                      now.year, now.month, now.day, pickedTime.hour, pickedTime.minute);

                  final formattedTime = DateFormat('HH:mm').format(dt);
                  controller.text = formattedTime;
                }
              },
              child: AbsorbPointer(
                child: TextField(
                  controller: controller,
                  style: TextStyle(color: colorProvider.secondColor),

                  decoration: InputDecoration(
                    filled: true,
                    fillColor: colorProvider.color.withOpacity(0.25),
                    hintText: labelText,
                    hintStyle: TextStyle(
                        color: colorProvider.secondColor.withOpacity(0.5)),
                    contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),

                    suffixIcon: Icon(Icons.access_time,
                        color: colorProvider.secondColor.withOpacity(0.7)),

                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}

FirebaseFirestore firestore = FirebaseFirestore.instance;
CollectionReference reports = firestore.collection('sadhana-reports');

Future<void> saveSadhanaReport( SadhanaReport report, String reportDate, double selectedExtraLecturePoints) async {

  try {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      debugPrint('No user is currently logged in.');
      return;
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    // 🔒 Normalize username (CRITICAL FIX)
    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    final CollectionReference dates = FirebaseFirestore.instance
        .collection('sadhana-reports') // explicit path
        .doc(userName)
        .collection('dates');

    final DocumentReference reportRef = dates.doc(reportDate);
    final DocumentSnapshot reportSnapshot = await reportRef.get();

    // Update scorecard ONLY if this is a new report
    if (!reportSnapshot.exists) {
      debugPrint('New report saved for user: $userName');

      ScorecardService().updateScorecard(
        userName,
        report.chantRounds,
        report.bookReading,
        report.classHearing,
        report.dailyServices,
      );
      await CompetitionService().updateScores(
        userName,
        report,
        DateFormat("dd-MM-yyyy").parse(reportDate),             // <-- reported date
        extraLecture: selectedExtraLecturePoints,
      );
    } else {
      debugPrint(
        'Report already exists for $userName on $reportDate. '
        'Scorecard not updated.',
      );
    }

    await reportRef.set(report.toMap());

    // 🔍 TEMP DEBUG (remove later)
    debugPrint(
      'SAVE → sadhana-reports/$userName/dates/$reportDate',
    );
  } catch (e) {
    debugPrint('Error saving report: $e');
  }
}

Future<bool> hasInternet() async {
  try {
    final result = await InternetAddress.lookup('example.com');
    if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
      return true;
    }
  } on SocketException catch (_) {
    return false;
  }
  return false;
}
