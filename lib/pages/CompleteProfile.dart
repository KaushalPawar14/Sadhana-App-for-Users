import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/ResidenceRule.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/Snackbar.dart';
import '../services/UpdateToken.dart';
import 'package:intl/intl.dart';

import '../theme/FolkTheme.dart';
import '../theme/FolkTokens.dart';
import '../utils/Commitments.dart';
import '../utils/ManualEntryMatch.dart';
import '../utils/StudentNameGuard.dart';
import '../widgets/FolkChip.dart';
import '../widgets/FolkDialog.dart';
import '../widgets/FolkPageBackground.dart';
import '../widgets/FolkStatusBar.dart';
import '../widgets/GhostPlaceholder.dart';
import '../widgets/PrimaryButton.dart';
import '../widgets/SadhanaFormWidgets.dart';

/// Registration's second step — reworked around mobile verification
/// (Master Task, 2026-09-11, Part 2).
///
/// ---------------------------------------------------------------------------
/// What this screen used to do, before this rework
/// ---------------------------------------------------------------------------
/// Previously: Role (residence) dropdown first, then mobile number (no
/// verification, no confirm step), then DOB, then optional chanting
/// commitment — all four submitted together in one `.set(..., merge:
/// true)`. `name` was never touched here; it was written once, up front, by
/// `Welcome.dart`, derived automatically from the student's Google account
/// `displayName`.
///
/// ---------------------------------------------------------------------------
/// What changed, and why
/// ---------------------------------------------------------------------------
/// `Welcome.dart` no longer derives or writes `name` at all — the student
/// now types their own full name, here, alongside their mobile number,
/// which is what lets it be checked precisely against a guide's manual
/// entry (Google's `displayName` can't be verified against anything). Name
/// and mobile are collected FIRST, with nothing else on screen, exactly
/// mirroring the old two-step shape (name used to be resolved before this
/// screen ever showed; now it's resolved as this screen's own first step).
///
/// Once both are filled, "Confirm" runs two checks — the SAME
/// name-uniqueness rule this app has always enforced
/// (`StudentNameGuard.dart`, unchanged) and a new mobile-number check
/// against every guide-recorded manual entry
/// (`utils/ManualEntryMatch.dart`, mirroring
/// `functions/manualStudents.js`'s own `findMatchingManualEntries`) — then
/// asks the student to confirm the number itself (it can never be changed
/// afterward, same immutability guarantee `name` has always had). Once
/// confirmed, both fields lock and the rest of the form appears below, on
/// this SAME page — no second screen.
///
///  * Mobile MATCHES a guide's manual entry: only date of birth and
///    chanting commitment appear. Residence is never shown and never
///    asked — the guide already recorded it, and per the product owner's
///    explicit decision it stays permanently guide-controlled for these
///    students, forever (Part 2 item 4). Enforced in CODE, not just by
///    hiding the field: this screen never includes `role` in what it
///    writes for a matched student — the value submitted is the manual
///    entry's own `role`, carried forward unedited, never a
///    student-provided one — and `functions/manualStudents.js`'s merge
///    unconditionally re-asserts that same value from the manual entry
///    itself as the authoritative, server-side source of truth,
///    independent of anything this client does.
///  * Mobile does NOT match: date of birth, chanting commitment, AND
///    residence (FOLK / Hostel / Localite) all appear, exactly as before.
///
/// Nothing about the actual Firestore write this screen performs changes
/// in shape: still one `.set(..., merge: true)` on `users/{uid}` that adds
/// `mobileNumber` for the first time — still exactly the write
/// `mergeManualEntryOnRegistration` (Cloud Function) watches for. No
/// parallel merge path is added here.
///
/// ---------------------------------------------------------------------------
/// Resuming a partially-completed registration (Rule 3 — must not regress)
/// ---------------------------------------------------------------------------
/// Real, already-registered students exist whose `name`/`role`/
/// `mobileNumber` were already written under the OLD flow before this
/// screen re-opens for them again (e.g. an existing student who registered
/// before the `dob` field existed, and only needs to supply that; or a
/// student who quit the app between the two old writes). Whichever of
/// `name` / `mobileNumber` / `role` already has a real value is treated as
/// already locked and is never re-asked or re-verified here — only fields
/// that are genuinely still missing are shown. The "Confirm" step (and the
/// mobile-match check behind it) only ever runs for a mobile number that
/// isn't saved yet.
class CompleteProfilePage extends StatefulWidget {
  const CompleteProfilePage({super.key});

  @override
  State<CompleteProfilePage> createState() => _CompleteProfilePageState();
}

class _CompleteProfilePageState extends State<CompleteProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController nameController = TextEditingController();
  final TextEditingController mobileController = TextEditingController();
  final TextEditingController commitmentRoundsController =
      TextEditingController();
  // Daily reading commitment in minutes (0 = a beginner), asked with the chanting one.
  final TextEditingController readingCommitmentController =
      TextEditingController();

  bool isLoading = true;
  bool isSubmitting = false;
  bool isVerifying = false;

  /// True once name+mobile are locked in — either just now (fresh
  /// registration, right after the confirm dialog) or already, from a
  /// prior save under the old flow. Gates whether step 1 (name+mobile) or
  /// step 2 (dob/commitment/[residence]) is shown.
  bool confirmed = false;

  bool nameAlreadySaved = false;
  bool mobileAlreadySaved = false;

  // Same save-once pattern as name: asked only when unsaved, locked after Confirm.
  bool genderAlreadySaved = false;
  bool genderLocked = false;
  String? selectedGender;

  /// Non-null only once resolved (freshly, or from resuming a
  /// mobile-already-saved-but-role-still-missing state) — null means "not a
  /// manual-entry match," never "not yet checked," by the time [confirmed]
  /// is true.
  bool isMatched = false;

  /// The residence value to submit for a MATCHED student — the manual
  /// entry's OWN `role`, carried forward unedited. Never shown, never
  /// student-editable; see this file's own header.
  String? matchedRole;

  /// Only asked when `role` isn't already fixed some other way (neither an
  /// existing saved `role`, nor a matched manual entry's own `role`).
  String? selectedResidence;
  bool get roleAlreadyLocked => (_existingRole ?? '').isNotEmpty;
  String? _existingRole;

  String? nameError;

  DateTime? dob;
  bool dobLocked = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    try {
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();

      if (userDoc.exists) {
        var userData = userDoc.data() as Map<String, dynamic>;

        final existingName = (userData['name'] ?? '').toString();
        if (existingName.isNotEmpty) {
          nameController.text = existingName;
          nameAlreadySaved = true;
        }

        final existingMobile = (userData['mobileNumber'] ?? '').toString();
        if (existingMobile.isNotEmpty) {
          mobileController.text = existingMobile;
          mobileAlreadySaved = true;
        }

        final existingGender = (userData['gender'] ?? '').toString();
        if (existingGender == 'male' || existingGender == 'female') {
          selectedGender = existingGender;
          genderAlreadySaved = true;
        }

        _existingRole = (userData['role'] ?? '').toString();

        // A mobile number already saved but no role yet is exactly the
        // "confirmed, awaiting the rest of the form" state — re-run the
        // same match check a fresh confirm would, purely to know whether
        // residence should appear, without re-asking the student anything.
        if (mobileAlreadySaved && !roleAlreadyLocked) {
          await _checkMobileMatch(existingMobile);
        }

        // Both already present → this is a resume, not a fresh start;
        // nothing to confirm, go straight to whatever's still missing.
        if (nameAlreadySaved && mobileAlreadySaved) {
          confirmed = true;
        }

        if (userData['dob'] is Timestamp) {
          dob = (userData['dob'] as Timestamp).toDate();
          dobLocked = true;
        }
        final commitment = userData['commitmentRounds'];
        if (commitment is num && commitment > 0) {
          commitmentRoundsController.text = commitment.toInt().toString();
        }
        final reading = userData['readingCommitmentMinutes'];
        if (reading is num && reading >= 0) {
          readingCommitmentController.text = reading.toInt().toString();
        }
      }
    } catch (e) {
      print('Error fetching user data: $e');
    }

    setState(() {
      isLoading = false;
    });
  }

  /// Runs the manual-entry match check for an already-normalized-format
  /// mobile number and records the result — shared by the fresh-confirm
  /// path and the resume-from-a-saved-mobile path above.
  Future<void> _checkMobileMatch(String rawMobile) async {
    final normalized = normalizeMobileNumber(rawMobile);
    final matches = await findMatchingManualEntries(normalized);
    if (matches.length == 1) {
      isMatched = true;
      matchedRole = (matches.first['role'] ?? '').toString();
      if (matchedRole!.isEmpty) matchedRole = null;
    } else {
      // Zero matches, or more than one (ambiguous — the server-side merge
      // trigger already refuses to guess in that case and flags it for a
      // human instead; the client falls back to treating it like "no
      // match" so the student still gets a residence field to fill in).
      isMatched = false;
      matchedRole = null;
    }
  }

  /// Only ever re-validates/re-checks whichever of name/mobile isn't
  /// ALREADY saved from a prior visit — an already-saved value was already
  /// checked (and, for name, is immutable) the first time round, so it is
  /// never re-run through `isStudentNameTaken` or the mobile-match check
  /// again here. See this file's own "Resuming a partially-completed
  /// registration" header note.
  // Leading and trailing spaces never stay in the name: the field shows the trimmed name as
  // soon as the student leaves it (the same value that is checked and saved).
  void _trimNameField() {
    if (nameAlreadySaved || confirmed) return;
    final trimmed = normalizeStudentName(nameController.text);
    if (trimmed != nameController.text) {
      setState(() => nameController.text = trimmed);
    }
  }

  Future<bool> _confirmNameAndMobile() async {
    setState(() => nameError = null);

    if (!genderAlreadySaved && selectedGender == null) {
      showSnackbar(context, 'Select Male or Female', Colors.redAccent,
          Icons.error);
      return false;
    }

    var normalizedName = nameController.text;
    if (!nameAlreadySaved) {
      normalizedName = normalizeStudentName(nameController.text);
      if (normalizedName.isEmpty) {
        setState(() => nameError = 'Full name is required');
        return false;
      }
    }

    if (!mobileAlreadySaved &&
        !RegExp(r'^\d{10}$').hasMatch(mobileController.text)) {
      showSnackbar(context, 'Enter a valid 10-digit mobile number',
          Colors.redAccent, Icons.error);
      return false;
    }

    setState(() => isVerifying = true);

    if (!nameAlreadySaved) {
      final taken = await isStudentNameTaken(normalizedName);
      if (taken) {
        setState(() {
          isVerifying = false;
          nameError = kNameTakenMessage;
        });
        return false;
      }
    }

    if (!mobileAlreadySaved) {
      await _checkMobileMatch(mobileController.text);
    }
    // else: isMatched/matchedRole were already resolved by _fetchUserData().

    setState(() => isVerifying = false);

    if (!mobileAlreadySaved) {
      if (!mounted) return false;
      final proceed = await _confirmMobileDialog(mobileController.text);
      if (proceed != true) return false;
    }

    if (!nameAlreadySaved) nameController.text = normalizedName;
    setState(() {
      confirmed = true;
      genderLocked = true;
    });
    return true;
  }

  Future<bool?> _confirmMobileDialog(String mobile) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final colors = dialogContext.folk;
        final text = dialogContext.folkText;
        return FolkDialog.alert(
          dialogContext,
          title: 'Confirm your mobile number',
          content: Text(
            'You entered "$mobile". This cannot be changed once you '
            'continue. Is this correct?',
            style: text.small,
          ),
          actions: [
            TextButton(
              style: FolkDialog.quietButton(colors, text),
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Edit'),
            ),
            ElevatedButton(
              style: FolkDialog.primaryButton(colors, text),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  /// Bounds are deliberately wide but sane: nobody in FOLK was born before
  /// 1950, and a birth date inside the last 10 years is a typo rather than a
  /// student.
  Future<void> _pickDob(FormFieldState<DateTime> state) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: dob ?? DateTime(now.year - 20),
      firstDate: DateTime(1950),
      lastDate: DateTime(now.year - 10, now.month, now.day),
      helpText: 'Select your date of birth',
    );

    if (picked == null) return;

    setState(() => dob = picked);
    state.didChange(picked);
    state.validate();
  }

  bool get showResidenceField => !roleAlreadyLocked && !isMatched;

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (!genderAlreadySaved && selectedGender == null) {
      showSnackbar(context, 'Select Male or Female', Colors.redAccent,
          Icons.error);
      return;
    }
    if (showResidenceField && (selectedResidence ?? '').isEmpty) {
      showSnackbar(context, 'Select FOLK, Hostel or Localite', Colors.redAccent,
          Icons.error);
      return;
    }

    // "Stay at FOLK" is for boys only. Whether a girl picked it or a guide's entry
    // assigned it, that combination is never written: stop here, before anything
    // is saved.
    final residenceToWrite = roleAlreadyLocked
        ? null
        : (isMatched ? matchedRole : selectedResidence);
    if (folkForbidden(selectedGender, residenceToWrite)) {
      showSnackbar(
          context,
          isMatched ? kContactGuideToRegister : kFolkBoysOnlyNote,
          Colors.redAccent,
          Icons.error);
      return;
    }

    setState(() {
      isSubmitting = true;
    });

    try {
      User? currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;

      final commitmentText = commitmentRoundsController.text.trim();
      final commitmentRounds =
          commitmentText.isEmpty ? null : int.tryParse(commitmentText);
      final readingText = readingCommitmentController.text.trim();
      final readingCommitment =
          readingText.isEmpty ? null : parseReadingCommitment(readingText);

      // Residence resolution — Part 2 item 4 / this file's own header:
      //  - already locked from a prior save → leave untouched (omit key).
      //  - matched a manual entry → the guide's own value, carried
      //    forward, never student-provided.
      //  - otherwise → the student's own selection.
      final String? roleToWrite = roleAlreadyLocked
          ? null
          : (isMatched ? matchedRole : selectedResidence);

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .set({
        if (!nameAlreadySaved) 'name': normalizeStudentName(nameController.text),
        if (!genderAlreadySaved) 'gender': selectedGender,
        if (!mobileAlreadySaved) 'mobileNumber': mobileController.text,
        if (roleToWrite != null && roleToWrite.isNotEmpty)
          'role': roleToWrite,
        if (dob != null) 'dob': Timestamp.fromDate(dob!),
        if (commitmentRounds != null && commitmentRounds > 0)
          'commitmentRounds': commitmentRounds,
        if (readingCommitment != null)
          'readingCommitmentMinutes': readingCommitment,
        'uid': currentUser.uid,
      }, SetOptions(merge: true));

      final resolvedRole = _existingRole?.isNotEmpty == true
          ? _existingRole!
          : (roleToWrite ?? '');

      // The student now has a name, so their push token can be saved (it was skipped at
      // app start while the name was still empty).
      updateFCMToken();

      showSnackbar(context, "Profile Updated Successfully", Colors.green,
          Icons.thumb_up);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (context) => CurvedNavBar(resolvedRole)),
        (route) => false,
      );
    } catch (e) {
      print('Error updating profile: $e');
      showSnackbar(context, "Process Failed", Colors.redAccent, Icons.thumb_down);
    }

    setState(() {
      isSubmitting = false;
    });
  }

  /// Back-button fix (2026-09-03) — same bug and same fix as
  /// `pages/Questions.dart`'s own `build()`: no `PopScope`/`WillPopScope`
  /// at all before this fix, so a hardware back press with the keyboard
  /// open could close the app instead of just the keyboard. Same
  /// `PopScope<Object?>` + `canPop: false` idiom, same `viewInsets.bottom >
  /// 0` keyboard-open check — with one addition the other, always-pushed
  /// screens don't need: this page is also rendered with an EMPTY back
  /// stack (`AnimatedLogin`'s own `home:` `FutureBuilder`, `main.dart`), so
  /// a plain `Navigator.of(context).pop()` on keyboard-closed would
  /// silently do nothing there instead of exiting the app — the correct,
  /// pre-existing behaviour for a root screen once the keyboard is already
  /// closed. `Navigator.canPop()` tells the two cases apart at pop-time.
  // A small label above a field.
  Widget _label(String text) =>
      Text(text, style: context.folkText.bodyStrong);

  Widget _formGhost() {
    return const GhostScope(
      child: Padding(
        padding: EdgeInsets.all(FolkSpace.pagePadding),
        child: Column(
          children: [
            GhostPlaceholder(
                width: double.infinity, height: 40, radius: 12, showBars: false),
            SizedBox(height: FolkSpace.xxl),
            GhostPlaceholder(
                width: double.infinity,
                height: 56,
                radius: FolkShape.tileRadius,
                showBars: false),
            SizedBox(height: FolkSpace.lg),
            GhostPlaceholder(
                width: double.infinity,
                height: 56,
                radius: FolkShape.tileRadius,
                showBars: false),
            SizedBox(height: FolkSpace.lg),
            GhostPlaceholder(
                width: double.infinity,
                height: 56,
                radius: FolkShape.tileRadius,
                showBars: false),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.folk;
    final text = context.folkText;
    // A locked (already saved or just confirmed) field keeps its value but is
    // muted and carries a lock.
    InputDecoration lockedAware(String hint, {String? errorText, required bool locked}) =>
        sadhanaFieldDecoration(
          context,
          hint: hint,
          errorText: errorText,
          suffixIcon: locked
              ? Icon(Icons.lock_outline_rounded, size: 18, color: colors.mutedText)
              : null,
        );
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (MediaQuery.of(context).viewInsets.bottom > 0) {
          FocusScope.of(context).unfocus();
          return;
        }
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: FolkStatusBar(
        child: Scaffold(
          backgroundColor: colors.pageBackground,
          body: FolkPageBackground(
            child: isLoading
                ? SafeArea(child: _formGhost())
                : SafeArea(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(FolkSpace.pagePadding,
                          FolkSpace.xxl, FolkSpace.pagePadding, 40),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Complete Your Profile',
                                style: text.screenTitle),
                            const SizedBox(height: FolkSpace.xxl),

                            // Full name
                            _label('Full Name'),
                            const SizedBox(height: FolkSpace.sm),
                            TextFormField(
                              controller: nameController,
                              enabled: !confirmed && !nameAlreadySaved,
                              onEditingComplete: _trimNameField,
                              onTapOutside: (_) => _trimNameField(),
                              style: text.body.copyWith(
                                  color: (!confirmed && !nameAlreadySaved)
                                      ? colors.text
                                      : colors.mutedText),
                              decoration: lockedAware('Enter your full name',
                                  errorText: nameError,
                                  locked: confirmed || nameAlreadySaved),
                              validator: (val) =>
                                  (val == null || val.trim().isEmpty)
                                      ? 'Full name is required'
                                      : null,
                            ),

                            const SizedBox(height: FolkSpace.xl),

                            // Gender — required, saved once, hidden when already saved.
                            if (!genderAlreadySaved) ...[
                              _label('Gender'),
                              const SizedBox(height: FolkSpace.sm),
                              Wrap(
                                spacing: FolkSpace.md,
                                runSpacing: FolkSpace.sm,
                                children: [
                                  for (final option in const [
                                    ('male', 'Male'),
                                    ('female', 'Female'),
                                  ])
                                    FolkChip(
                                      label: option.$2,
                                      selected: selectedGender == option.$1,
                                      selectedStyle: FolkGradientStyle.violet,
                                      large: true,
                                      onTap: genderLocked
                                          ? null
                                          : () => setState(() {
                                                selectedGender = option.$1;
                                                // "Stay at FOLK" is for boys only.
                                                if (folkForbidden(selectedGender,
                                                    selectedResidence)) {
                                                  selectedResidence = null;
                                                }
                                              }),
                                    ),
                                ],
                              ),
                              const SizedBox(height: FolkSpace.xl),
                            ],

                            // Mobile number
                            _label('Mobile Number'),
                            const SizedBox(height: FolkSpace.sm),
                            TextFormField(
                              controller: mobileController,
                              keyboardType: TextInputType.phone,
                              enabled: !confirmed && !mobileAlreadySaved,
                              style: text.body.copyWith(
                                  color: (!confirmed && !mobileAlreadySaved)
                                      ? colors.text
                                      : colors.mutedText),
                              decoration: lockedAware('Enter your mobile number',
                                  locked: confirmed || mobileAlreadySaved),
                              validator: (val) {
                                if (val == null || val.isEmpty) {
                                  return 'Mobile number is required';
                                }
                                if (!RegExp(r'^\d{10}$').hasMatch(val)) {
                                  return 'Enter a valid 10-digit number';
                                }
                                return null;
                              },
                            ),

                            if (!confirmed) ...[
                              const SizedBox(height: FolkSpace.xl),
                              PrimaryButton(
                                label: 'Confirm',
                                loading: isVerifying,
                                onPressed: (isVerifying ||
                                        (!genderAlreadySaved &&
                                            selectedGender == null))
                                    ? null
                                    : () => _confirmNameAndMobile(),
                              ),
                            ],

                            if (confirmed) ...[
                              const SizedBox(height: FolkSpace.xl),

                              // Date of birth
                              _label('Date of Birth'),
                              const SizedBox(height: FolkSpace.sm),
                              FormField<DateTime>(
                                validator: (_) =>
                                    dob == null ? 'Date of birth is required' : null,
                                builder: (state) {
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      InkWell(
                                        borderRadius: BorderRadius.circular(
                                            FolkShape.tileRadius),
                                        onTap: dobLocked
                                            ? null
                                            : () => _pickDob(state),
                                        child: InputDecorator(
                                          decoration: sadhanaFieldDecoration(
                                            context,
                                            suffixIcon: Icon(
                                              dobLocked
                                                  ? Icons.lock_outline_rounded
                                                  : Icons.calendar_today,
                                              size: 20,
                                              color: dobLocked
                                                  ? colors.mutedText
                                                  : colors.text,
                                            ),
                                          ),
                                          child: Text(
                                            dob == null
                                                ? 'Select your date of birth'
                                                : DateFormat('dd MMM yyyy')
                                                    .format(dob!),
                                            style: dob == null
                                                ? text.body.copyWith(
                                                    color: colors.mutedText)
                                                : text.body,
                                          ),
                                        ),
                                      ),
                                      if (state.hasError)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 16, top: 6),
                                          child: Text(
                                            state.errorText!,
                                            style: text.caption.copyWith(
                                                color: colors.calendarMissedText),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),

                              const SizedBox(height: FolkSpace.xl),

                              // Chanting commitment — OPTIONAL.
                              _label(
                                  'How many rounds do you commit to chant daily? (optional)'),
                              const SizedBox(height: FolkSpace.sm),
                              TextFormField(
                                controller: commitmentRoundsController,
                                keyboardType: TextInputType.number,
                                style: text.body,
                                decoration: sadhanaFieldDecoration(context,
                                    hint: 'e.g. 16'),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return null;
                                  final n = int.tryParse(val.trim());
                                  if (n == null || n <= 0) {
                                    return 'Enter a whole number greater than 0, or leave blank';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: FolkSpace.xl),

                              // Reading commitment — minutes a day; 0 is fine for a beginner.
                              _label(
                                  'How many minutes of reading do you commit to daily? (0 if you are a beginner)'),
                              const SizedBox(height: FolkSpace.sm),
                              TextFormField(
                                controller: readingCommitmentController,
                                keyboardType: TextInputType.number,
                                style: text.body,
                                decoration: sadhanaFieldDecoration(context,
                                    hint: 'e.g. 30, or 0'),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) return null;
                                  if (parseReadingCommitment(val) == null) {
                                    return 'Enter minutes from 0 to 1440, or leave blank';
                                  }
                                  return null;
                                },
                              ),

                              // Residence — only ever asked when it isn't already
                              // fixed some other way. See this file's own header.
                              if (showResidenceField) ...[
                                const SizedBox(height: FolkSpace.xl),
                                _label('Residence'),
                                const SizedBox(height: FolkSpace.sm),
                                DropdownButtonFormField<String>(
                                  value: selectedResidence,
                                  dropdownColor: colors.surface,
                                  style: text.body,
                                  // A girl is offered Hostel and Localite only.
                                  items: [
                                    for (final residence
                                        in residenceChoices(selectedGender))
                                      DropdownMenuItem(
                                          value: residence,
                                          child: Text(residence)),
                                  ],
                                  onChanged: (val) =>
                                      setState(() => selectedResidence = val),
                                  decoration: sadhanaFieldDecoration(context),
                                ),
                                if (selectedGender == 'female')
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(kFolkBoysOnlyNote,
                                        style: text.caption),
                                  ),
                              ],

                              const SizedBox(height: 32),

                              PrimaryButton(
                                label: 'Submit',
                                loading: isSubmitting,
                                onPressed: isSubmitting ? null : _submitForm,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
