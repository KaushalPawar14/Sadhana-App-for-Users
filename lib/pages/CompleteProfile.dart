import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:folk_app/utils/BottomNavBar.dart';
import 'package:folk_app/utils/Snackbar.dart';
import 'package:intl/intl.dart';
import 'package:sizer/sizer.dart';

import '../utils/MalaLoading.dart';
import '../utils/ManualEntryMatch.dart';
import '../utils/StudentNameGuard.dart';

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
  Future<bool> _confirmNameAndMobile() async {
    setState(() => nameError = null);

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
    });
    return true;
  }

  Future<bool?> _confirmMobileDialog(String mobile) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Confirm your mobile number'),
          content: Text(
            'You entered "$mobile". This cannot be changed once you '
            'continue. Is this correct?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Edit'),
            ),
            TextButton(
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
    if (showResidenceField && (selectedResidence ?? '').isEmpty) {
      showSnackbar(context, 'Select FOLK, Hostel or Localite', Colors.redAccent,
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
        if (!nameAlreadySaved) 'name': nameController.text,
        if (!mobileAlreadySaved) 'mobileNumber': mobileController.text,
        if (roleToWrite != null && roleToWrite.isNotEmpty)
          'role': roleToWrite,
        if (dob != null) 'dob': Timestamp.fromDate(dob!),
        if (commitmentRounds != null && commitmentRounds > 0)
          'commitmentRounds': commitmentRounds,
        'uid': currentUser.uid,
      }, SetOptions(merge: true));

      final resolvedRole = _existingRole?.isNotEmpty == true
          ? _existingRole!
          : (roleToWrite ?? '');

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
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
      body: isLoading
          ? CustomLoader()
          : SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 4.h),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Complete Your Profile',
                    style: TextStyle(
                        fontSize: 24.sp, fontWeight: FontWeight.bold)),
                SizedBox(height: 4.h),

                // Full name
                Text('Full Name',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 1.h),
                TextFormField(
                  controller: nameController,
                  enabled: !confirmed && !nameAlreadySaved,
                  decoration: InputDecoration(
                    hintText: 'Enter your full name',
                    errorText: nameError,
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 5.w, vertical: 1.5.h),
                  ),
                  validator: (val) => (val == null || val.trim().isEmpty)
                      ? 'Full name is required'
                      : null,
                ),

                SizedBox(height: 2.h),

                // Mobile number
                Text('Mobile Number',
                    style: TextStyle(
                        fontSize: 16.sp, fontWeight: FontWeight.w600)),
                SizedBox(height: 1.h),
                TextFormField(
                  controller: mobileController,
                  keyboardType: TextInputType.phone,
                  enabled: !confirmed && !mobileAlreadySaved,
                  decoration: InputDecoration(
                    hintText: 'Enter your mobile number',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                        horizontal: 5.w, vertical: 1.5.h),
                  ),
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
                  SizedBox(height: 2.h),
                  ElevatedButton(
                    onPressed: isVerifying
                        ? null
                        : () => _confirmNameAndMobile(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: EdgeInsets.symmetric(vertical: 1.6.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isVerifying
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : Text(
                            'Confirm',
                            style: TextStyle(
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w500,
                                color: Colors.white),
                          ),
                  ),
                ],

                if (confirmed) ...[
                  SizedBox(height: 2.h),

                  // Date of birth
                  Text('Date of Birth',
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                  SizedBox(height: 1.h),
                  FormField<DateTime>(
                    validator: (_) =>
                        dob == null ? 'Date of birth is required' : null,
                    builder: (state) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: dobLocked ? null : () => _pickDob(state),
                            child: InputDecorator(
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 5.w, vertical: 1.5.h),
                                suffixIcon: Icon(
                                  Icons.calendar_today,
                                  size: 18.sp,
                                  color: dobLocked ? Colors.grey : null,
                                ),
                              ),
                              child: Text(
                                dob == null
                                    ? 'Select your date of birth'
                                    : DateFormat('dd MMM yyyy').format(dob!),
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  color: dob == null ? Colors.grey : null,
                                ),
                              ),
                            ),
                          ),
                          if (state.hasError)
                            Padding(
                              padding: EdgeInsets.only(left: 4.w, top: 0.8.h),
                              child: Text(
                                state.errorText!,
                                style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12.sp),
                              ),
                            ),
                        ],
                      );
                    },
                  ),

                  SizedBox(height: 2.h),

                  // Chanting commitment — OPTIONAL.
                  Text('How many rounds do you commit to chant daily? (optional)',
                      style: TextStyle(
                          fontSize: 16.sp, fontWeight: FontWeight.w600)),
                  SizedBox(height: 1.h),
                  TextFormField(
                    controller: commitmentRoundsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'e.g. 16',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 5.w, vertical: 1.5.h),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return null;
                      final n = int.tryParse(val.trim());
                      if (n == null || n <= 0) {
                        return 'Enter a whole number greater than 0, or leave blank';
                      }
                      return null;
                    },
                  ),

                  // Residence — only ever asked when it isn't already
                  // fixed some other way. See this file's own header.
                  if (showResidenceField) ...[
                    SizedBox(height: 2.h),
                    Text('Residence',
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.w600)),
                    SizedBox(height: 1.h),
                    DropdownButtonFormField<String>(
                      value: selectedResidence,
                      items: const [
                        DropdownMenuItem(
                            value: 'Stay at FOLK',
                            child: Text('Stay at FOLK')),
                        DropdownMenuItem(
                            value: 'Stay at Hostel',
                            child: Text('Stay at Hostel')),
                        DropdownMenuItem(
                            value: 'Stay at Localite',
                            child: Text('Stay at Localite')),
                      ],
                      onChanged: (val) =>
                          setState(() => selectedResidence = val),
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 5.w, vertical: 1.5.h),
                      ),
                    ),
                  ],

                  SizedBox(height: 4.h),

                  ElevatedButton(
                    onPressed: isSubmitting ? null : _submitForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: EdgeInsets.symmetric(vertical: 2.h),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: isSubmitting
                        ? CustomLoader()
                        : Center(
                      child: Text(
                        'Submit',
                        style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w500,
                            color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}
