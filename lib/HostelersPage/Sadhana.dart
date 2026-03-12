import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/models/HostelSadhana.dart';
import 'package:folk_app/services/SendNotifications.dart';
import 'package:folk_app/utils/ColorProvider.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class SadhanaPage extends StatefulWidget {
  @override
  State<SadhanaPage> createState() => SadhanaPageState();
}

class SadhanaPageState extends State<SadhanaPage> {
  TextEditingController dateController = TextEditingController();
  TextEditingController roundsController = TextEditingController();
  TextEditingController bookController = TextEditingController();
  TextEditingController wakeUpTimeController = TextEditingController();
  TextEditingController sleepTime = TextEditingController();
  TextEditingController japaFinish = TextEditingController();
  // TextEditingController sleepHours = TextEditingController();

  Map<int, int?> selectedOptions = {};
  Map<int, String> answers = {};

  void submitQuiz() async {
    FocusScope.of(context).requestFocus(FocusNode());

    // Fill answers from controllers
    answers[0] = wakeUpTimeController.text;
    answers[4] = dateController.text;
    answers[5] = roundsController.text;
    answers[6] = bookController.text;
    answers[7] = japaFinish.text;
    answers[3] = sleepTime.text;

    // ======= VALIDATION: CHECK ALL FIELDS BEFORE SUBMITTING =======
    bool allFilled = wakeUpTimeController.text.isNotEmpty &&
        dateController.text.isNotEmpty &&
        roundsController.text.isNotEmpty &&
        bookController.text.isNotEmpty &&
        sleepTime.text.isNotEmpty &&
        japaFinish.text.isNotEmpty &&
        selectedOptions.containsKey(2); // SB

    if (!allFilled) {
      showSnackbar(context, 'Please fill all the fields!', Colors.black45,
          CupertinoIcons.info);
      return;
    }

    print(answers);

    String? Rounds = answers[5];
    String? bookRead = answers[6];
    String? Hearing = answers[2];
    String? wakeUpTime = answers[0];
    String? japaEnd = answers[7];
    String reversedDate = reverseDateFormat(answers[4]!);
    String? Sleeping = answers[3];

    TimeOfDay parsedWakeUpTime = _parseTime(wakeUpTime!);
    TimeOfDay parsedFinishTiming = _parseTime(japaEnd!);
    TimeOfDay parsedSleepingTiming = _parseTime(Sleeping!);

    String sentence =
        "📿: $Rounds rounds,  📖 : $bookRead mins\n👂 : $Hearing points ,  🙇🏻‍♂️ : $japaEnd";

    print(sentence);
    showSnackbar(context, 'Sadhana submitted successfully',
        CupertinoColors.activeGreen, Icons.done_outline_rounded);

    setState(() {
      answers.clear();
      dateController.clear();
      bookController.clear();
      roundsController.clear();
      sleepTime.clear();
      japaFinish.clear();
      wakeUpTimeController.clear();
      selectedOptions.clear();
    });

    sendNotificationToAdmin(reversedDate, wakeUpTime, Sleeping, sentence);
    print(
        'Report Data: $reversedDate, $wakeUpTime, $Rounds, $bookRead, $Hearing, $japaEnd');

    HostelSadhana newReport = HostelSadhana(
        wakeUpTime: parsedWakeUpTime,
        chantRounds: int.parse(Rounds!),
        bookReading: int.parse(bookRead!),
        classHearing: int.parse(Hearing!),
        finishTiming: parsedFinishTiming,
        sleepTiming: parsedSleepingTiming);
    print('New Report created: ${newReport.toMap()}');
    await saveSadhanaReport(newReport, reversedDate);
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

  @override
  Widget build(BuildContext context) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Scaffold(
        backgroundColor: colorProvider.color,
        body: SingleChildScrollView(
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
                    question: "Sleep time of yesterday",
                    controller: sleepTime,
                    labelText: "HH : MM",
                    context: context),
                const SizedBox(height: 20),
                buildQuestionTimePicker(
                    question: "Waking Up Time for today?",
                    controller: wakeUpTimeController,
                    labelText: "HH : MM",
                    context: context),
                const SizedBox(height: 20),
                buildQuestionTextField(
                  question: "Total rounds chanted yesterday",
                  controller: roundsController,
                  labelText: "Total rounds",
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 20),
                buildQuestionDropdown(
                  question: "Heard Bhagavatam Class today ?",
                  questionId: 2,
                  optionsMap: {
                    "2": "Fully",
                    "1": "Partial",
                    "0": "Missed",
                  },
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
                    question: "Japa finish time of yesterday",
                    controller: japaFinish,
                    labelText: "HH : MM",
                    context: context),
                const SizedBox(height: 20),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    elevation: 5,
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
      throw Exception(
          "Number of options does not match the options list length");
    }

    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Card(
        color: colorProvider.fourthColor,
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorProvider.secondColor,
                ),
              ),
              const SizedBox(height: 10),
              for (int i = 0; i < options.length; i++)
                ListTile(
                  title: Text(
                    options[i],
                    style: TextStyle(color: colorProvider.secondColor),
                  ),
                  leading: Radio<int>(
                    value: i,
                    activeColor: colorProvider.secondColor,
                    groupValue: selectedOptions[questionId],
                    onChanged: (value) {
                      setState(() {
                        selectedOptions[questionId] = value;
                        answers[questionId] = options[value!];
                      });
                    },
                  ),
                ),
              SizedBox(height: 10),
              if (text != null)
                Text(
                  text,
                  style: TextStyle(color: colorProvider.secondColor),
                ),
            ],
          ),
        ),
      );
    });
  }

  Widget buildQuestionDropdown({
    required String question,
    required int questionId,
    required Map<String, String> optionsMap, // key = value, value = explanation
  }) {
    return Consumer<ColorProvider>(builder: (context, colorProvider, child) {
      return Card(
        color: colorProvider.fourthColor,
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorProvider.secondColor,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: answers[questionId], // currently selected value
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                dropdownColor: colorProvider.color,
                items: optionsMap.entries.map((entry) {
                  return DropdownMenuItem<String>(
                    value: entry.key,
                    child: Text("${entry.key} - ${entry.value}",
                        style: TextStyle(color: colorProvider.secondColor)),
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
      return Card(
        color: colorProvider.fourthColor,
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        elevation: 0.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorProvider.secondColor,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                child: TextField(
                  controller: controller,
                  keyboardType: keyboardType,
                  style: TextStyle(color: colorProvider.secondColor),
                  decoration: InputDecoration(
                    labelText: labelText,
                    labelStyle: TextStyle(color: colorProvider.secondColor),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                  onTap: onTap,
                ),
              ),
            ],
          ),
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
      return Card(
        color: colorProvider.fourthColor,
        margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        elevation: .5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                question,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorProvider.secondColor,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () async {
                  final TimeOfDay? pickedTime = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay.now(),
                  );
                  if (pickedTime != null) {
                    final now = DateTime.now();
                    final dt = DateTime(now.year, now.month, now.day,
                        pickedTime.hour, pickedTime.minute);
                    final formattedTime = DateFormat('HH:mm').format(dt);
                    controller.text = formattedTime;
                  }
                },
                child: AbsorbPointer(
                  child: TextField(
                    controller: controller,
                    cursorColor: colorProvider.secondColor,
                    style: TextStyle(color: colorProvider.secondColor),
                    decoration: InputDecoration(
                      labelText: labelText,
                      labelStyle: TextStyle(color: colorProvider.secondColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

FirebaseFirestore firestore = FirebaseFirestore.instance;

Future<void> saveSadhanaReport(HostelSadhana report, String reportDate) async {
  try {
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      print('❌ No user is currently logged in.');
      return;
    }

    // Fetch user document to get username
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (!userDoc.exists) {
      print('❌ User document not found for UID: ${currentUser.uid}');
      return;
    }

    String userName = userDoc.data()?['name'] ?? 'Unknown User';

    // Reference to new collection "HostelSadhana/{userName}/dates/{reportDate}"
    final reportRef = FirebaseFirestore.instance
        .collection('hostel-sadhana')
        .doc(userName)
        .collection('dates')
        .doc(reportDate);

    // Save the report data
    await reportRef.set(report.toMap(), SetOptions(merge: true));

    print(
        '📌 HostelSadhana report saved successfully for $userName on $reportDate');
  } catch (e) {
    print('❌ Error saving HostelSadhana report: $e');
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
