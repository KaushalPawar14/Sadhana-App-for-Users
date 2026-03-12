import 'dart:convert';
import 'package:folk_app/services/AccessToken.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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
    );
  }

  // Handle notification when the app is opened
  void handleMessage(RemoteMessage? message) {
    if (message != null) {
      print('Notification clicked: ${message.notification?.title}');
      // You can add any additional logic for handling the message when the app is opened
    }
  }

  // Send notification using FCM token
  Future<void> sendTokenNotification(String token, String title, String message) async {
    try {
      final body = {
        'message': {
          'token': token,
          'notification': {
            'body': message,
            'title': title,
          },
        },
      };

      String url = 'https://fcm.googleapis.com/v1/projects/folk-sadhana-app/messages:send';
      String accessKey = await AccessTokenFirebase().getAccessToken();

      await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $accessKey',
        },
        body: jsonEncode(body),
      ).then((value) {
        print('Status code ${value.statusCode}');
      });
    } catch (e) {
      print(e);
    }
  }
}
