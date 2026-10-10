import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Today's message — the one place the app asks for it. It is generated, at most
// once per student per day, as soon as the student opens (or comes back to) the
// app, so it is usually ready before they reach Journey; Journey and Ask both
// read it from here. The server's `generateDailyEncouragement` is idempotent
// per student per day (a second call returns the message that exists, with no
// second AI call); this service adds the client half: ONE call in flight per
// student per day on this device, shared by every caller.
//
// The message is cached on the device (uid + date + text), so on the next open
// Journey shows it at once and only re-checks quietly in the background.

enum DailyMessageStatus {
  // Not known yet: being read or generated.
  loading,

  // Today's message is here.
  ready,

  // The student has not accepted the Ask disclosure yet: nothing is generated
  // (that message lands in the guide-visible transcript the disclosure covers).
  needsDisclosure,

  // Generation failed; it is tried again on the next app open.
  failed,
}

@immutable
class DailyMessageState {
  const DailyMessageState(this.status, {this.text, this.uid, this.date});

  final DailyMessageStatus status;
  final String? text;
  final String? uid;
  final String? date;

  @override
  bool operator ==(Object other) =>
      other is DailyMessageState &&
      other.status == status &&
      other.text == text &&
      other.uid == uid &&
      other.date == date;

  @override
  int get hashCode => Object.hash(status, text, uid, date);
}

// `isNew`: a message was written for today on this device (Ask reloads its
// transcript when true). `failed`: a genuine failure.
typedef DailyMessageResult = ({bool isNew, bool failed, String? text});

const Duration kDailyMessageTimeout = Duration(seconds: 45);

class DailyMessageService {
  DailyMessageService({
    this.currentUid,
    this.callGenerate,
    this.readDisclosure,
    this.readExisting,
    this.loadPrefs,
    this.today,
  });

  // The app's own service. Tests build their own with the hooks below.
  static final DailyMessageService instance = DailyMessageService();

  final String? Function()? currentUid;
  final Future<Map<String, dynamic>> Function()? callGenerate;
  final Future<bool> Function(String uid)? readDisclosure;
  final Future<String?> Function(String uid, String date)? readExisting;
  final Future<SharedPreferences> Function()? loadPrefs;
  final String Function()? today;

  final ValueNotifier<DailyMessageState> state =
      ValueNotifier(const DailyMessageState(DailyMessageStatus.loading));

  Future<DailyMessageResult>? _flight;
  String? _flightKey;
  Future<void>? _opening;
  String? _generatedKey;

  // The student+day already confirmed against the server in this run, so
  // coming back to the app later the same day does no further reads.
  String? _verifiedKey;

  String _today() =>
      (today ?? () => DateFormat('dd-MM-yyyy').format(DateTime.now()))();
  String? _uid() =>
      currentUid != null ? currentUid!() : FirebaseAuth.instance.currentUser?.uid;
  String _key(String uid, String date) => '$uid|$date';

  // ------------------------------------------------------------------ opening

  // Called when the signed-in app opens or resumes. Never throws.
  Future<void> onAppOpened() {
    return _opening ??= _open().whenComplete(() => _opening = null);
  }

  Future<void> _open() async {
    try {
      final uid = _uid();
      if (uid == null || uid.isEmpty) return;
      final date = _today();
      if (_verifiedKey == _key(uid, date) &&
          state.value.status == DailyMessageStatus.ready) {
        return;
      }

      // 1. The device cache: shown at once.
      final cached = await _readCache(uid, date);
      if (cached != null) {
        _set(DailyMessageState(DailyMessageStatus.ready,
            text: cached, uid: uid, date: date));
      } else if (state.value.uid != uid ||
          state.value.date != date ||
          state.value.status == DailyMessageStatus.ready) {
        _set(DailyMessageState(DailyMessageStatus.loading, uid: uid, date: date));
      }

      // 2. Only a student who accepted the Ask disclosure gets a message made.
      final accepted = await _disclosureAccepted(uid);
      if (!accepted) {
        if (cached == null) {
          _set(DailyMessageState(DailyMessageStatus.needsDisclosure,
              uid: uid, date: date));
        }
        return;
      }

      // 3. A message may already exist (made on another device, or by Ask):
      //    read it; that costs no generation.
      final existing = await _readExisting(uid, date);
      if (existing != null && existing.isNotEmpty) {
        await _remember(uid, date, existing);
        _verifiedKey = _key(uid, date);
        return;
      }
      if (cached != null) return; // cached and still being checked: keep showing it

      // 4. Nothing yet today: generate it, in the background.
      await ensureToday(uid);
    } catch (_) {
      if (state.value.status != DailyMessageStatus.ready) {
        _set(DailyMessageState(DailyMessageStatus.failed,
            uid: state.value.uid, date: state.value.date));
      }
    }
  }

  // ------------------------------------------------------------- generating

  // Today's message for [uid], generating it if it does not exist: the one
  // call to the callable. If a call for this student and day is already in
  // flight, this joins it; if the message is already known, no call is made.
  Future<DailyMessageResult> ensureToday(String uid) {
    final date = _today();
    final key = _key(uid, date);

    if (_flight != null && _flightKey == key) return _flight!;

    final s = state.value;
    if (s.status == DailyMessageStatus.ready &&
        s.uid == uid &&
        s.date == date &&
        (s.text ?? '').isNotEmpty) {
      return Future.value(
          (isNew: _generatedKey == key, failed: false, text: s.text));
    }

    _flightKey = key;
    final flight = _generate(uid, date, key);
    _flight = flight;
    flight.whenComplete(() {
      if (identical(_flight, flight)) {
        _flight = null;
        _flightKey = null;
      }
    });
    return flight;
  }

  Future<DailyMessageResult> _generate(String uid, String date, String key) async {
    _set(DailyMessageState(DailyMessageStatus.loading, uid: uid, date: date));
    try {
      final data = await (callGenerate ?? _callCallable)();
      final isNew = data['isNew'] == true;
      final text = (data['text'] ?? '').toString().trim();
      if (isNew) _generatedKey = key;
      _verifiedKey = key;
      if (text.isNotEmpty) {
        await _remember(uid, date, text);
      } else {
        // Generated or existing, but no text came back: read it.
        final existing = await _readExisting(uid, date);
        if (existing != null && existing.isNotEmpty) {
          await _remember(uid, date, existing);
        }
      }
      return (isNew: isNew, failed: false, text: state.value.text);
    } catch (_) {
      _set(DailyMessageState(DailyMessageStatus.failed, uid: uid, date: date));
      return (isNew: false, failed: true, text: null);
    }
  }

  // The `generateDailyEncouragement` callable — the only caller in the app.
  static Future<Map<String, dynamic>> _callCallable() async {
    final callable =
        FirebaseFunctions.instanceFor(region: 'asia-south1').httpsCallable(
      'generateDailyEncouragement',
      options: HttpsCallableOptions(timeout: kDailyMessageTimeout),
    );
    final result = await callable.call<Map<String, dynamic>>();
    return Map<String, dynamic>.from(result.data);
  }

  // ------------------------------------------------------------------ pieces

  Future<bool> _disclosureAccepted(String uid) async {
    if (readDisclosure != null) return readDisclosure!(uid);
    final snap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    return snap.data()?['acknowledgedDisclosure'] == true;
  }

  // The same read Ask makes for today's transcript, narrowed to the daily
  // message: `sessionDate` equal to today's key and `entryType` daily_message.
  Future<String?> _readExisting(String uid, String date) async {
    if (readExisting != null) return readExisting!(uid, date);
    final snap = await FirebaseFirestore.instance
        .collection('studentChats')
        .doc(uid)
        .collection('messages')
        .where('sessionDate', isEqualTo: date)
        .where('entryType', isEqualTo: 'daily_message')
        .get();
    final docs = snap.docs.toList()
      ..sort((a, b) {
        final ta = a.data()['createdAt'];
        final tb = b.data()['createdAt'];
        if (ta is! Timestamp) return -1;
        if (tb is! Timestamp) return 1;
        return ta.compareTo(tb);
      });
    if (docs.isEmpty) return null;
    final text = (docs.first.data()['text'] ?? '').toString().trim();
    return text.isEmpty ? null : text;
  }

  // ------------------------------------------------------------------- cache

  static const String _kCache = 'dailyMessage.cache';

  Future<SharedPreferences> _prefs() =>
      (loadPrefs ?? SharedPreferences.getInstance)();

  Future<String?> _readCache(String uid, String date) async {
    try {
      final raw = (await _prefs()).getString(_kCache);
      if (raw == null) return null;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      if (map['uid'] == uid && map['date'] == date) {
        final text = (map['text'] ?? '').toString();
        return text.isEmpty ? null : text;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _remember(String uid, String date, String text) async {
    _set(DailyMessageState(DailyMessageStatus.ready,
        text: text, uid: uid, date: date));
    try {
      await (await _prefs()).setString(
          _kCache, jsonEncode({'uid': uid, 'date': date, 'text': text}));
    } catch (_) {}
  }

  void _set(DailyMessageState next) {
    if (state.value != next) state.value = next;
  }
}
