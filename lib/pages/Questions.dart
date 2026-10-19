import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:folk_app/theme/FolkTheme.dart';
import 'package:folk_app/utils/SadhanaSave.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import '../models/SadhanaReports.dart';
import '../utils/Commitments.dart';
import '../services/ScorecardUpdate.dart';
import '../widgets/FolkScaffold.dart';
import '../widgets/PrimaryButton.dart';
import '../widgets/SadhanaFormWidgets.dart';

class QuestionsPage extends StatefulWidget {
  const QuestionsPage({
    super.key,
    this.saveReport,
    this.saveTimeout = kSadhanaSaveTimeout,
    this.initialDate,
    this.loadCommitments,
  });

  // A missed day tapped on the calendar opens the form with that date already in the
  // Date of Submission field (yyyy-MM-dd, exactly what the date picker writes, so the
  // validation and the save are the same as for a date picked by hand). Null (the
  // Submit button) leaves the field empty.
  final DateTime? initialDate;


  // Tests hand in their own save so no real Submit reaches Firestore; the app
  // never sets these, and `saveSadhanaReport` below is what runs.
  @visibleForTesting
  final Future<void> Function(
          SadhanaReport report, String reportDate, double extraLecture)?
      saveReport;
  @visibleForTesting
  final Duration saveTimeout;

  // Tests hand in the commitments; the app reads them from the student's profile.
  @visibleForTesting
  final Future<Commitments> Function()? loadCommitments;

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

  // Dates whose score has already been added in this session. A retry after a
  // failed save must not add the same day's points a second time.
  final Set<String> _scoringAttempted = <String>{};

  Future<void> _saveReport(
          SadhanaReport report, String reportDate, double extraLecture) =>
      (widget.saveReport ??
          (r, d, e) =>
              saveSadhanaReport(r, d, e, scoringAttempted: _scoringAttempted))(
          report, reportDate, extraLecture);

  Future<void> submitQuiz() async {
    if (_saving) return;
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

    // ======= LOGIC CHANGE: VALIDATE AND PARSE EVERY NUMBER FIRST =======
    // Nothing is written, and nothing is cleared, unless all of these pass.
    final int? roundsValue = parseWholeNumber(roundsController.text);
    final int? bookValue = parseWholeNumber(bookController.text);
    final int? hearingValue = int.tryParse(answers[2] ?? '');
    final int? serviceValue = int.tryParse(answers[3] ?? '');
    final errors = <String, String>{
      if (roundsValue == null) 'rounds': kWholeNumberMessage,
      if (bookValue == null) 'book': kWholeNumberMessage,
      // Required before, but never saved; checked like the other numbers.
      if (parseWholeNumber(academicsStudy.text) == null)
        'academics': kWholeNumberMessage,
      if (hearingValue == null) 'class': 'Choose an answer',
      if (serviceValue == null) 'service': 'Choose an answer',
      if (tryParseTime(templeEntered.text) == null)
        'temple': 'Pick this time again',
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

    // Typo guard (no cap on the points): far more than the commitment asks first.
    final commitments = await (widget.loadCommitments ?? loadMyCommitments)();
    if (!mounted) return;
    if (looksLikeTypo(roundsValue!, commitments.rounds) &&
        !await confirmUnusualAmount(context,
            what: 'Rounds chanted', entered: roundsValue, unit: 'rounds')) {
      return;
    }
    if (!mounted) return;
    final readingTarget = commitments.readingMinutes ?? 0;
    if (looksLikeTypo(bookValue!, readingTarget) &&
        !await confirmUnusualAmount(context,
            what: 'Reading', entered: bookValue, unit: 'minutes')) {
      return;
    }
    if (!mounted) return;

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
    // A sleep time after midnight (00:00-11:59) is saved as 23:59.
    TimeOfDay parsedSleepingTiming = normalizeSleepTime(_parseTime(Sleeping!));

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

    // Master Task follow-up (2026-09-03) — the old hardcoded-guide broadcast
    // (sendNotificationToAdmin, ["SBSD", "AMHD"] regardless of this
    // student's real guide) was removed here. The student's own guide and
    // the HOD are now notified server-side, correctly, by
    // `functions/submissionNotify.js`'s `onDocumentCreated` trigger on this
    // same write — see that file's own header.
    print(
        'Report Data: $reversedDate, $timeEntered, $Rounds, $bookRead, $Hearing, ${serviceDone}, $japaEnd');

    SadhanaReport newReport = SadhanaReport(
        templeEntry: parsedTempleEntry,
        chantRounds: roundsValue,
        bookReading: bookValue,
        classHearing: hearingValue!,
        dailyServices: serviceValue!,
        finishTiming: parsedFinishTiming,
        sleepTiming: parsedSleepingTiming);
    print('New Report created: ${newReport.toMap()}');

    // ======= LOGIC CHANGE: SAVE FIRST; CLEAR AND CONFIRM ONLY ON SUCCESS =======
    setState(() => _saving = true);
    try {
      await runSadhanaSave(
          () => _saveReport(newReport, reversedDate, extraLecturePoints),
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
      academicsStudy.clear();
      // sleepHours.clear();
      sleepTime.clear();
      japaFinish.clear();
      templeEntered.clear();
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
  
  /// Back-button fix (2026-09-03) — with the keyboard open, the hardware
  /// back button/gesture was closing the entire app instead of just the
  /// keyboard. This page had NO `PopScope`/`WillPopScope` at all before this
  /// fix, leaving back handling entirely to the platform's own default —
  /// on this Flutter/Android combination that default does not reliably
  /// resolve "keyboard open, back pressed" to "dismiss keyboard, stay on
  /// this route": it can fall through to the OS's own default action
  /// (finishing the Activity) instead, since nothing here ever registers an
  /// explicit callback for the system to hand the gesture to. There is no
  /// pushAndRemoveUntil anywhere in this app's navigation to this page
  /// (confirmed by grep — `Calendar.dart`'s only route here is a plain
  /// `Navigator.push`) and no existing PopScope with a wrong return value
  /// either — the bug is the absence of one, not a mistake in one.
  ///
  /// Same `PopScope<Object?>` + `canPop: false` idiom already used
  /// elsewhere in this app (`BookReaderPage.dart`, `BookPageList.dart`'s
  /// commitment dialog) — not a new pattern. `viewInsets.bottom > 0` is the
  /// standard proxy for "the on-screen keyboard is showing." `canPop: false`
  /// means every pop attempt — system back AND `Navigator.pop(context)`
  /// from anywhere in this subtree — is intercepted here, so this is the one
  /// place that decides: keyboard open -> unfocus and stay; keyboard closed
  /// -> pop for real, explicitly, through this app's own Navigator rather
  /// than left ambiguous.
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
          physics: BouncingScrollPhysics(),
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
                  question: "Time Entered Temple Hall",
                  errorKey: 'temple',
                  controller: templeEntered,
                  labelText: "HH : MM",
                  // The picker opens on 5:00 AM.
                  initialTime: const TimeOfDay(hour: 5, minute: 0),
                  context: context),
              const SizedBox(height: 8),
              buildQuestionDropdown(
                question: "SB Class - 7:20 AM to 7:55 AM",
                questionId: 2,
                optionsMap: {
                  "2": "Fully",
                  "1": "Partial",
                  "0": "Missed",
                },
              ),
              const SizedBox(height: 8),
              buildQuestionTextField(
                  question: "Total Academics Study yesterday",
                  errorKey: 'academics',
                  controller: academicsStudy,
                  labelText: "in mins",
                  keyboardType: TextInputType.number),
              const SizedBox(height: 8),
              buildQuestionDropdown(
                question: "Daily Assigned Services",
                questionId: 3,
                optionsMap: {
                  "2": "Done fully",
                  "1": "Done partially",
                  "0": "Not done",
                },
              ),
              const SizedBox(height: 8),
              buildQuestionTextField(
                question: "Total rounds chanted yesterday",
                errorKey: 'rounds',
                controller: roundsController,
                labelText: "Total rounds",
                keyboardType: TextInputType.number,
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
                  question: "Japa finish time of yesterday",
                  errorKey: 'japa',
                  controller: japaFinish,
                  labelText: "HH : MM",
                  context: context),
              const SizedBox(height: 8),
              buildQuestionCard(
                question: "Heard extra lecture yesterday ?",
                questionId: 9,
                numberOfOptions: 3,
                options: ["more than 30 mins", "more than 15 mins", "No"],
              ),
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
      throw Exception("Number of options does not match");
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
CollectionReference reports = firestore.collection('sadhana-reports');

// LOGIC CHANGES (save path): this no longer swallows its own failures: the catch
// still logs, then rethrows. A missing user, a missing users document, or a
// missing name stops BEFORE any write (a report is never filed under a made-up
// name) and throws. The reads and the single write below are unchanged; the
// only edit inside is that a retry does not add a day's score twice
// (`scoringAttempted`).
Future<void> saveSadhanaReport(
  SadhanaReport report,
  String reportDate,
  double selectedExtraLecturePoints, {
  Set<String>? scoringAttempted,
}) async {
  try {
    final User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw const SadhanaSaveException(SadhanaSaveFailure.profileIncomplete);
    }

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .get();

    // 🔒 Normalize username (CRITICAL FIX)
    String userName = requireStudentName(
        userExists: userDoc.exists, storedName: userDoc.data()?['name']);

    final CollectionReference dates = FirebaseFirestore.instance
        .collection('sadhana-reports') // explicit path
        .doc(userName)
        .collection('dates');

    final DocumentReference reportRef = dates.doc(reportDate);
    final DocumentSnapshot reportSnapshot = await reportRef.get();

    // Update scorecard ONLY if this is a new report
    // (and not when an earlier attempt for this date already added the points)
    if (!reportSnapshot.exists &&
        !(scoringAttempted?.contains(reportDate) ?? false)) {
      debugPrint('New report saved for user: $userName');

      ScorecardService().updateScorecard(
        userName,
        report.chantRounds,
        report.bookReading,
        report.classHearing,
        report.dailyServices,
      );
      scoringAttempted?.add(reportDate);
    } else {
      debugPrint(
        'Report already exists for $userName on $reportDate. '
        'Scorecard not updated.',
      );
    }

    // ⚠️ `SetOptions(merge: true)` added 2026-08-23, matching the hostel path.
    //
    // This was a BARE `.set()` — a whole-document replace. Any field not in
    // `report.toMap()` was deleted on every resubmission, which meant the japa
    // counter's `chantRounds` increments (ChantingScreen.dart) were silently
    // erased whenever a student submitted the form again the same day. It also
    // made the new fields below impossible: they would have been wiped by the
    // next submission. The merge lands FIRST, for exactly that reason.
    //
    // Nothing is lost by merging: `toMap()` supplies every field this document
    // has ever held, so the merge writes the same values the replace did.
    final bool isNewReport = !reportSnapshot.exists;
    final existing = reportSnapshot.data() as Map<String, dynamic>?;
    final int japaSoFar = existing?['japaCounterRounds'] is num
        ? (existing!['japaCounterRounds'] as num).toInt()
        : 0;

    await reportRef.set({
      ...report.toMap(),
      // The extra-lecture answer (0 none, 1 more than 15 mins, 2 more than 30 mins),
      // which the server's point system reads (it used to be used only on the phone).
      'extraLecture': selectedExtraLecturePoints.toInt(),
      // `chantRounds` stays exactly what the form typed — unchanged behaviour.
      // `roundsSource` only *describes* the document; no existing reader is
      // repointed by this change (that is a separate, later decision).
      'roundsSource': japaSoFar > 0 ? 'both' : 'form',
      'updatedAt': FieldValue.serverTimestamp(),
      // Only on creation, so a resubmission never rewrites the original.
      if (isNewReport) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    // 🔍 TEMP DEBUG (remove later)
    debugPrint(
      'SAVE → sadhana-reports/$userName/dates/$reportDate',
    );
  } catch (e) {
    debugPrint('Error saving report: $e');
    rethrow;
  }
}
