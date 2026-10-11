import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/models/HostelSadhana.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SadhanaSave.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import 'package:folk_app/widgets/FolkScaffold.dart';
import 'package:folk_app/widgets/PrimaryButton.dart';
import 'package:folk_app/widgets/SadhanaFormWidgets.dart';

class SadhanaPage extends StatefulWidget {
  const SadhanaPage({
    super.key,
    this.saveReport,
    this.saveTimeout = kSadhanaSaveTimeout,
    this.initialDate,
  });

  // A missed day tapped on the calendar opens the form with that date already in the
  // Date of Submission field (yyyy-MM-dd, exactly what the date picker writes, so the
  // validation and the save are the same as for a date picked by hand). Null (the
  // Submit button) leaves the field empty.
  final DateTime? initialDate;


  // Tests hand in their own save so no real Submit reaches Firestore; the app
  // never sets these, and `saveSadhanaReport` below is what runs.
  @visibleForTesting
  final Future<void> Function(HostelSadhana report, String reportDate)?
      saveReport;
  @visibleForTesting
  final Duration saveTimeout;

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

  // LOGIC CHANGES (save path): the button is busy while a save runs, and a field
  // the last Submit rejected shows its message until it is edited.
  bool _saving = false;
  final SadhanaFieldErrors _errors = SadhanaFieldErrors();

  @override
  void initState() {
    super.initState();
    final d = widget.initialDate;
    if (d != null) dateController.text = d.toString().split(' ')[0];
  }

  @override
  void dispose() {
    _errors.dispose();
    super.dispose();
  }

  Future<void> _saveReport(HostelSadhana report, String reportDate) =>
      (widget.saveReport ?? saveSadhanaReport)(report, reportDate);

  Future<void> submitQuiz() async {
    if (_saving) return;
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

    // ======= LOGIC CHANGE: VALIDATE AND PARSE EVERY NUMBER FIRST =======
    // Nothing is written, and nothing is cleared, unless all of these pass.
    final int? roundsValue = parseWholeNumber(roundsController.text);
    final int? bookValue = parseWholeNumber(bookController.text);
    final int? hearingValue = int.tryParse(answers[2] ?? '');
    final errors = <String, String>{
      if (roundsValue == null) 'rounds': kWholeNumberMessage,
      if (bookValue == null) 'book': kWholeNumberMessage,
      if (hearingValue == null) 'class': 'Choose an answer',
      if (tryParseTime(wakeUpTimeController.text) == null)
        'wake': 'Pick this time again',
      if (tryParseTime(sleepTime.text) == null) 'sleep': 'Pick this time again',
      if (tryParseTime(japaFinish.text) == null) 'japa': 'Pick this time again',
      if (DateTime.tryParse(dateController.text) == null)
        'date': 'Pick the date again',
    };
    if (errors.isNotEmpty) {
      _errors.set(errors);
      showSnackbar(context, 'Please correct the highlighted fields.',
          Colors.black45, CupertinoIcons.info);
      return;
    }
    _errors.clear();

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
    // A sleep time after midnight (00:00-11:59) is saved as 23:59.
    TimeOfDay parsedSleepingTiming = normalizeSleepTime(_parseTime(Sleeping!));

    // Master Task follow-up (2026-09-03) — the old hardcoded-guide broadcast
    // (sendNotificationToAdmin, ["SBSD", "AMHD"] regardless of this
    // student's real guide) was removed here, same as Questions.dart's own
    // submission path. The student's own guide and the HOD are now notified
    // server-side, correctly, by `functions/submissionNotify.js`'s
    // `notifyGuideOnHostelSadhana` trigger on this same write.
    print(
        'Report Data: $reversedDate, $wakeUpTime, $Rounds, $bookRead, $Hearing, $japaEnd');

    HostelSadhana newReport = HostelSadhana(
        wakeUpTime: parsedWakeUpTime,
        chantRounds: roundsValue!,
        bookReading: bookValue!,
        classHearing: hearingValue!,
        finishTiming: parsedFinishTiming,
        sleepTiming: parsedSleepingTiming);
    print('New Report created: ${newReport.toMap()}');

    // ======= LOGIC CHANGE: SAVE FIRST; CLEAR AND CONFIRM ONLY ON SUCCESS =======
    setState(() => _saving = true);
    try {
      await runSadhanaSave(() => _saveReport(newReport, reversedDate),
          timeout: widget.saveTimeout);
    } on SadhanaSaveException catch (e) {
      // Everything the student typed stays where it is.
      if (!mounted) return;
      setState(() => _saving = false);
      showSnackbar(context, sadhanaSaveMessage(e.failure),
          Colors.red.shade700, Icons.error_outline);
      return;
    }

    if (!mounted) return;
    showSnackbar(context, 'Sadhana submitted successfully',
        CupertinoColors.activeGreen, Icons.done_outline_rounded);

    setState(() {
      _saving = false;
      answers.clear();
      dateController.clear();
      bookController.clear();
      roundsController.clear();
      sleepTime.clear();
      japaFinish.clear();
      wakeUpTimeController.clear();
      selectedOptions.clear();
    });
  }

  Future<void> SelectDate() async {
    DateTime? pickedDate = await showDatePicker(
        context: context,
        // Opened from a missed day: the picker starts on that date (still editable).
        initialDate: widget.initialDate ?? DateTime.now(),
        firstDate: DateTime(2000),
        lastDate: DateTime.now());
    if (pickedDate != null) {
      // Only the date field changes: its controller repaints it.
      dateController.text = pickedDate.toString().split(" ")[0];
      _errors.remove('date');
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

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`, see that method's doc comment
  /// for the full investigation. This screen had the identical gap: no
  /// `PopScope`/`WillPopScope` at all, so a hardware back press with the
  /// keyboard open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check.
  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
          return;
        }
        Navigator.of(context).pop();
      },
      child: FolkScaffold(
        title: "Submit Sadhana",
        body: SingleChildScrollView(
          padding: kSadhanaFormPadding,
          child: Column(
            children: [
              buildQuestionTextField(
                  question: "Date of Submission",
                  errorKey: 'date',
                  controller: dateController,
                  labelText: "Enter Date",
                  keyboardType: TextInputType.none,
                  onTap: () {
                    SelectDate();
                  }),
              const SizedBox(height: 8),
              buildQuestionTimePicker(
                  question: "Sleep time of yesterday",
                  errorKey: 'sleep',
                  controller: sleepTime,
                  labelText: "HH : MM",
                  // The picker opens on 10:00 PM; a time after midnight is
                  // recorded as 11:59 PM.
                  initialTime: const TimeOfDay(hour: 22, minute: 0),
                  sleepRule: true,
                  context: context),
              const SizedBox(height: 8),
              buildQuestionTimePicker(
                  question: "Waking Up Time for today?",
                  errorKey: 'wake',
                  controller: wakeUpTimeController,
                  labelText: "HH : MM",
                  context: context),
              const SizedBox(height: 8),
              buildQuestionTextField(
                question: "Total rounds chanted yesterday",
                errorKey: 'rounds',
                controller: roundsController,
                labelText: "Total rounds",
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              buildQuestionDropdown(
                question: "Heard Bhagavatam Class today ?",
                questionId: 2,
                optionsMap: {
                  "2": "Fully",
                  "1": "Partial",
                  "0": "Missed",
                },
              ),
              const SizedBox(height: 8),
              buildQuestionTextField(
                question: "Total book reading (in mins) yesterday",
                errorKey: 'book',
                controller: bookController,
                labelText: "Total reading",
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              buildQuestionTimePicker(
                  question: "Japa finish time of yesterday",
                  errorKey: 'japa',
                  controller: japaFinish,
                  labelText: "HH : MM",
                  context: context),
              const SizedBox(height: 20),
              PrimaryButton(
                label: "Submit",
                loading: _saving,
                onPressed: _saving ? null : submitQuiz,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _clearFieldError(String? key) {
    _errors.remove(key);
  }

  Widget buildQuestionCard({
    required String question,
    required int questionId,
    required int numberOfOptions,
    required List<String> options,
    String? text,
  }) {
    if (options.length != numberOfOptions) {
      throw Exception("Number of options does not match the options list length");
    }

    final style = context.folkText;
    return FormQuestionCard(
      question: question,
      // Choosing an option rebuilds this card only, not the whole form.
      child: StatefulBuilder(
        builder: (context, setCard) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < options.length; i++)
              FormOptionRow(
                label: options[i],
                selected: selectedOptions[questionId] == i,
                onTap: () {
                  selectedOptions[questionId] = i;
                  answers[questionId] = options[i];
                  setCard(() {});
                },
              ),
            if (text != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(text, style: style.caption),
              ),
          ],
        ),
      ),
    );
  }

  Widget buildQuestionDropdown({
    required String question,
    required int questionId,
    required Map<String, String> optionsMap,
  }) {
    final colors = context.folk;
    final style = context.folkText;
    return FormQuestionCard(
      question: question,
      // Choosing an answer rebuilds this card only, not the whole form.
      child: StatefulBuilder(
        builder: (context, setCard) => DropdownButtonFormField<String>(
          value: answers[questionId],
          dropdownColor: colors.surface,
          style: style.body,
          decoration: sadhanaFieldDecoration(context),
          items: optionsMap.entries.map((entry) {
            return DropdownMenuItem<String>(
              value: entry.key,
              child: Text("${entry.key} - ${entry.value}", style: style.body),
            );
          }).toList(),
          onChanged: (value) {
            answers[questionId] = value!;
            selectedOptions[questionId] = int.parse(value);
            setCard(() {});
          },
        ),
      ),
    );
  }

  Widget buildQuestionTextField({
    required String question,
    required TextEditingController controller,
    required String labelText,
    required TextInputType keyboardType,
    Function()? onTap,
    String? errorKey,
  }) {
    final style = context.folkText;
    return FormQuestionCard(
      question: question,
      child: sadhanaErrorBuilder(
        _errors,
        errorKey,
        (error) => TextField(
          controller: controller,
          keyboardType: keyboardType,
          onTap: onTap,
          onChanged: (_) => _clearFieldError(errorKey),
          style: style.body,
          decoration:
              sadhanaFieldDecoration(context, hint: labelText, errorText: error),
        ),
      ),
    );
  }

  Widget buildQuestionTimePicker({
    required String question,
    required TextEditingController controller,
    required String labelText,
    required BuildContext context,
    String? errorKey,
    // Where the picker opens (null: the current time, as before).
    TimeOfDay? initialTime,
    // The sleep field: a time after midnight is recorded as 11:59 PM, and a
    // small note says so.
    bool sleepRule = false,
  }) {
    final colors = this.context.folk;
    final style = this.context.folkText;
    final field = GestureDetector(
      onTap: () async {
        final TimeOfDay? pickedTime = await showTimePicker(
          context: context,
          initialTime: initialTime ?? TimeOfDay.now(),
        );

        if (pickedTime != null) {
          final chosen = sleepRule ? normalizeSleepTime(pickedTime) : pickedTime;
          final now = DateTime.now();
          final dt = DateTime(
              now.year, now.month, now.day, chosen.hour, chosen.minute);

          final formattedTime = DateFormat('HH:mm').format(dt);
          controller.text = formattedTime;
          _clearFieldError(errorKey);
        }
      },
      child: AbsorbPointer(
        child: sadhanaErrorBuilder(
          _errors,
          errorKey,
          (error) => TextField(
            controller: controller,
            style: style.body,
            decoration: sadhanaFieldDecoration(
              this.context,
              hint: labelText,
              suffixIcon: Icon(Icons.access_time, color: colors.mutedText),
              errorText: error,
            ),
          ),
        ),
      ),
    );
    return FormQuestionCard(
      question: question,
      child: !sleepRule
          ? field
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                field,
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(kSleepAfterMidnightNote, style: style.caption),
                ),
              ],
            ),
    );
  }
}

FirebaseFirestore firestore = FirebaseFirestore.instance;

// LOGIC CHANGES (save path): this no longer swallows its own failures: the catch
// still logs, then rethrows. A missing user, a missing users document, or a
// missing name stops BEFORE any write (a report is never filed under a made-up
// name) and throws. The reads and the single write below are unchanged.
Future<void> saveSadhanaReport(HostelSadhana report, String reportDate) async {
  try {
    User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      throw const SadhanaSaveException(SadhanaSaveFailure.profileIncomplete);
    }

    // Fetch user document to get username
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    String userName = requireStudentName(
        userExists: userDoc.exists, storedName: userDoc.data()?['name']);

    // Reference to new collection "HostelSadhana/{userName}/dates/{reportDate}"
    final reportRef = FirebaseFirestore.instance
        .collection('hostel-sadhana')
        .doc(userName)
        .collection('dates')
        .doc(reportDate);

    // Read first, so `createdAt` is written only on creation and
    // `roundsSource` can tell whether the japa counter has already contributed.
    // Added 2026-08-23 alongside the same change on the FOLK path
    // (`pages/Questions.dart`). `merge: true` was already correct here.
    final existingSnap = await reportRef.get();
    final bool isNewReport = !existingSnap.exists;
    final existing = existingSnap.data();
    final int japaSoFar = existing?['japaCounterRounds'] is num
        ? (existing!['japaCounterRounds'] as num).toInt()
        : 0;

    // Save the report data. `chantRounds` stays exactly what the form typed.
    await reportRef.set({
      ...report.toMap(),
      'roundsSource': japaSoFar > 0 ? 'both' : 'form',
      'updatedAt': FieldValue.serverTimestamp(),
      if (isNewReport) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    print(
        '📌 HostelSadhana report saved successfully for $userName on $reportDate');
  } catch (e) {
    print('❌ Error saving HostelSadhana report: $e');
    rethrow;
  }
}
