import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../utils/NotificationRouter.dart';

Future<void> handleBG(RemoteMessage message) async {
  // Handling background notifications
  print("Background notification received: ${message.notification?.title}");
  if (message.notification != null) {
    // You can show a local notification in the background (for consistency)
    await FirebaseCM().showLocalNotification(message);
  }
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
        android: AndroidInitializationSettings('@mipmap/ic_launcher'), // App icon for notification
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
  Future<void> handleForegroundNotification(RemoteMessage message) async {
    print('Foreground notification received: ${message.notification?.title}');
    if (message.notification != null) {
      // Show local notification when the app is in the foreground
      await showLocalNotification(message);
    }
  }

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
