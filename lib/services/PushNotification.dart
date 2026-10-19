import 'dart:ui' show Color;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/NotificationRouter.dart';

// Called by Firebase Messaging from native code, in its own isolate, when a message
// arrives with the app in the background or closed. It must be a top-level function
// AND carry this pragma: a release (AOT) build removes every function nothing in Dart
// refers to, and the native side cannot find an unannotated one
// ("To closurize ... from native code, it must be annotated").
@pragma('vm:entry-point')
Future<void> handleBG(RemoteMessage message) =>
    handleBackgroundMessage(message, show: (m) => FirebaseCM().showLocalNotification(m));

/// Draws a notification itself (a local one).
typedef ShowLocal = Future<void> Function(RemoteMessage message);

/// Should the APP draw a notification for [message]?
///
/// ONE notification per message, in every state of the app:
///  - A message that carries a `notification` payload (every push this system sends) is drawn BY ANDROID whenever the
///    app is in the background or closed. Firebase Messaging still runs [handleBG] for it, so drawing a local
///    notification there as well (what this app used to do) put a SECOND, identical notification on the screen: the
///    "8:00 reminder arrives twice" bug.
///  - In the foreground Android draws nothing, so the app draws it (once, from `onMessage`).
///  - A data-only message has nothing to show, as before.
bool shouldShowLocally(RemoteMessage message, {required bool foreground}) =>
    message.notification != null && foreground;

/// Background / closed app: Android has already drawn the notification, so nothing is drawn here.
Future<void> handleBackgroundMessage(RemoteMessage message, {required ShowLocal show}) async {
  print("Background notification received: ${message.notification?.title}");
  if (shouldShowLocally(message, foreground: false)) await show(message);
}

/// Foreground: Android draws nothing, so the app draws the notification, once.
Future<void> handleForegroundMessage(RemoteMessage message, {required ShowLocal show}) async {
  print('Foreground notification received: ${message.notification?.title}');
  if (shouldShowLocally(message, foreground: true)) await show(message);
}

class FirebaseCM {
  final firebaseMessaging = FirebaseMessaging.instance;

  final AndroidNotificationChannel channel = const AndroidNotificationChannel(
    'notification', // ID
    'notification', // Name
    importance: Importance.max,
    playSound: true,
    showBadge: true,
  );

  final localNotifications = FlutterLocalNotificationsPlugin();

  // Initialize notifications
  Future<void> initNotifications() async {
    NotificationSettings settings = await firebaseMessaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: true,
      criticalAlert: true,
      provisional: false,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      print('Permission denied');
    }

    if (FirebaseAuth.instance.currentUser != null) {
      final fcmToken = await firebaseMessaging.getToken();
      // Update FCM token if needed
    }

    FirebaseMessaging.onBackgroundMessage(handleBG); // Handles background notifications
    initPushNotifications(); // Handles foreground notifications
  }

  // Initialize foreground notifications
  Future<void> initPushNotifications() async {
    await localNotifications.initialize(
      InitializationSettings(
        android: AndroidInitializationSettings('@drawable/ic_stat_notification'), // white glyph on transparent
      ),
      // Deep-link routing (Master Task, 2026-09-10 — Part 3) — the ONE
      // launch state `getInitialMessage()`/`onMessageOpenedApp` below
      // cannot cover: the app already in the FOREGROUND when a
      // notification arrives never reaches those two (the OS only routes
      // a tap through them for a notification it displayed itself, i.e.
      // background/terminated) — it shows a LOCAL notification instead
      // (`showLocalNotification` below), and tapping THAT needed its own,
      // previously-unregistered callback. `payload` is a JSON-encoded
      // string of the same `message.data` map every other path routes
      // from, decoded back into a map here — `flutter_local_notifications`
      // only carries a plain string payload, not a structured map.
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        // Routing diagnostics (Master Task, 2026-09-10 — Part 1 item 2) —
        // real, on-device evidence for whichever of the four checkpoints
        // (payload arriving / handler firing / router called / navigator
        // key state) turns out to be where a future report of "still
        // doesn't route" actually breaks down.
        print('[notif-route] local notification tapped, payload=$payload');
        if (payload == null || payload.isEmpty) return;
        try {
          final data = jsonDecode(payload);
          if (data is Map) {
            routeNotification(Map<String, dynamic>.from(data));
          }
        } catch (_) {
          // Malformed payload — fails safe, same as an unrecognised `dest`.
        }
      },
    );

    // The channel exists from the first launch, so a notification Android draws itself (background / closed app) uses
    // it too (`default_notification_channel_id` in the manifest): same sound and pop-up as the foreground one.
    await localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Configure Firebase to show notifications in the foreground
    await firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Handle initial message when the app is opened from a notification
    firebaseMessaging.getInitialMessage().then(handleMessage);
    // Listen for notifications when the app is in the foreground
    FirebaseMessaging.onMessage.listen(handleForegroundNotification);
    // Handle notification when the app is opened from a notification
    FirebaseMessaging.onMessageOpenedApp.listen(handleMessage);
  }

  // Handle notifications in the foreground
  Future<void> handleForegroundNotification(RemoteMessage message) =>
      handleForegroundMessage(message, show: showLocalNotification);

  // Show a local notification (in foreground or background)
  Future<void> showLocalNotification(RemoteMessage message) async {
    await localNotifications.show(
      0, // Notification ID
      message.notification?.title, // Notification title
      message.notification?.body, // Notification body
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          importance: Importance.max,
          priority: Priority.high,
          showWhen: false,
          // The small icon is a white glyph on transparent (Android draws it as a
          // silhouette); the full-colour logo is the large icon.
          icon: 'ic_stat_notification',
          color: const Color(0xFFFCA925), // FOLK orange
          largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
        ),
      ),
      // Carries the SAME routing data this message arrived with, so a tap
      // on this locally-shown notification (the foreground case) routes
      // exactly like a tap on a real system notification does (Master
      // Task, 2026-09-10 — Part 3). `message.data` is always
      // `Map<String, String>`; JSON-encoding it is the only way to carry
      // it through `flutter_local_notifications`' plain-string payload.
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  // Handle notification when the app is opened
  void handleMessage(RemoteMessage? message) {
    // Routing diagnostics (Master Task, 2026-09-10 — Part 1 item 2) — this
    // is the handler `getInitialMessage()` (terminated launch) and
    // `onMessageOpenedApp` (backgrounded tap) both call; logging the raw
    // payload here is checkpoint 1 ("is the payload arriving") for both of
    // those launch states in one place.
    print('[notif-route] handleMessage fired, message=${message?.messageId}, '
        'data=${message?.data}');
    if (message != null) {
      print('Notification clicked: ${message.notification?.title}');
      routeNotification(message.data);
    }
  }

  // `sendTokenNotification` (direct client-side FCM v1 send, backed by a
  // bundled service-account key) removed entirely — task: "Remove the
  // embedded service-account key from the Student app". Its two call
  // sites (`AssociationScreen.dart`, `ExpeditionScreen.dart`) now rely on
  // `functions/associationNotify.js`/`expeditionNotify.js` reacting
  // server-side to the same Firestore writes those screens already made.
}
