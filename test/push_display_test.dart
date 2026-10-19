import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:folk_app/services/PushNotification.dart';

// One notification per message, in every state of the app.
//
// The 8:00 reminder arrived twice because, with the app in the background or closed, Android drew the notification
// itself (a message with a `notification` payload) AND Firebase Messaging ran `handleBG`, which drew a second one.

RemoteMessage message({bool notification = true, Map<String, String> data = const {'dest': 'student_calendar'}}) => RemoteMessage(
      messageId: 'm1',
      notification: notification ? const RemoteNotification(title: 'Fill your report', body: 'Please fill it') : null,
      data: data,
    );

enum AppState { foreground, background, terminated }

/// What the student sees for one message in one state: Android's own notification (background / closed, for a message
/// with a `notification` payload; the platform does this, outside the app) plus whatever the app draws itself.
Future<({int local, int system})> displays(RemoteMessage m, AppState state) async {
  var local = 0;
  Future<void> show(RemoteMessage _) async => local++;
  if (state == AppState.foreground) {
    await handleForegroundMessage(m, show: show);
  } else {
    // background and terminated both reach the app through the same background handler
    await handleBackgroundMessage(m, show: show);
  }
  final system = (m.notification != null && state != AppState.foreground) ? 1 : 0;
  return (local: local, system: system);
}

void main() {
  group('exactly one display per message, in every state', () {
    for (final state in AppState.values) {
      test('a notification message while the app is ${state.name}: one on screen', () async {
        final r = await displays(message(), state);
        expect(r.local + r.system, 1, reason: '${state.name}: local ${r.local} + system ${r.system}');
      });
    }

    test('foreground: the app draws it (Android draws nothing); background and closed: Android draws it, the app draws NOTHING', () async {
      expect(await displays(message(), AppState.foreground), (local: 1, system: 0));
      expect(await displays(message(), AppState.background), (local: 0, system: 1));
      expect(await displays(message(), AppState.terminated), (local: 0, system: 1));
    });

    test('many messages in a row: still one each', () async {
      for (final state in AppState.values) {
        var total = 0;
        for (var i = 0; i < 25; i++) {
          final r = await displays(message(), state);
          total += r.local + r.system;
        }
        expect(total, 25, reason: state.name);
      }
    });

    test('a data-only message has nothing to show in any state (as before)', () async {
      for (final state in AppState.values) {
        final r = await displays(message(notification: false), state);
        expect(r, (local: 0, system: 0), reason: state.name);
      }
    });

    test('every notification type is shown: the payload is not inspected, only its presence', () async {
      for (final dest in ['student_calendar', 'student_books', 'student_chanting', 'student_friends', 'student_expeditions', 'play_store', '']) {
        for (final state in AppState.values) {
          final r = await displays(message(data: dest.isEmpty ? const {} : {'dest': dest}), state);
          expect(r.local + r.system, 1, reason: '$dest / ${state.name}');
        }
      }
    });

    test('the policy', () {
      expect(shouldShowLocally(message(), foreground: true), isTrue);
      expect(shouldShowLocally(message(), foreground: false), isFalse);
      expect(shouldShowLocally(message(notification: false), foreground: true), isFalse);
    });
  });

  group('the wiring (source and manifest)', () {
    final src = File('lib/services/PushNotification.dart').readAsStringSync().replaceAll(RegExp(r'\r\n'), '\n');

    test('the background handler goes through the policy; it never draws a notification by itself', () {
      final i = src.indexOf('Future<void> handleBG(');
      final handleBg = src.substring(i, src.indexOf(';', i) + 1);
      expect(handleBg, contains('handleBackgroundMessage'));
      expect(handleBg.contains('showLocalNotification(message)'), isFalse);
      final j = src.indexOf('Future<void> handleBackgroundMessage(');
      final body = src.substring(j, src.indexOf('\n}\n', j));
      expect(body, contains('shouldShowLocally(message, foreground: false)'));
    });

    test('the foreground listener is registered once, and goes through the policy', () {
      expect('FirebaseMessaging.onMessage.listen('.allMatches(src).length, 1);
      expect('FirebaseMessaging.onBackgroundMessage('.allMatches(src).length, 1);
      expect(src, contains('handleForegroundMessage(message, show: showLocalNotification)'));
    });

    test('no notification is scheduled on the phone: no zonedSchedule, periodic show or WorkManager', () {
      final all = Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));
      for (final f in all) {
        final text = f.readAsStringSync();
        for (final banned in ['zonedSchedule', 'periodicallyShow', 'Workmanager', 'AndroidAlarmManager']) {
          expect(text.contains(banned), isFalse, reason: '${f.path} must not contain $banned');
        }
      }
      // and the only place a local notification is ever drawn is the one policy-guarded method
      final shows = all.where((f) => f.readAsStringSync().contains('localNotifications.show(')).map((f) => f.path.replaceAll(RegExp(r'\\'), '/'));
      expect(shows.toList(), ['lib/services/PushNotification.dart']);
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec.contains('workmanager'), isFalse);
      expect(pubspec.contains('android_alarm_manager'), isFalse);
    });

    test('Android draws a background notification in the same channel the app creates', () {
      final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest, contains('com.google.firebase.messaging.default_notification_channel_id'));
      expect(manifest, contains('android:value="notification"'));
      expect(src, contains("'notification', // ID"), reason: 'the channel the manifest points to is the one the app creates');
      expect(src, contains('createNotificationChannel(channel)'));
    });
  });

  group('a new trip: the route and the setting', () {
    test('tapping the push opens Expeditions', () {
      final router = File('lib/utils/NotificationRouter.dart').readAsStringSync();
      expect(router, contains("case 'student_expeditions':"));
      expect(router, contains('ExpeditionScreen('));
      expect(router, contains("import '../pages/ExpeditionScreen.dart';"));
    });

    test('the student can switch "New trips" off, under the exact key the server reads', () {
      final prefs = File('lib/pages/NotificationPreferences.dart').readAsStringSync();
      expect(prefs, contains("key: 'newTrip'"));
      expect(prefs, contains("title: 'New trips'"));
      final server = File('../../functions/tripNotify.js');
      if (server.existsSync()) expect(server.readAsStringSync(), contains('PREF_KEY = "newTrip"'));
    });
  });
}
