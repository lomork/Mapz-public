import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService _notificationService =
  NotificationService._internal();

  factory NotificationService() {
    return _notificationService;
  }

  NotificationService._internal();
  static const int _discoveryNotificationId = 1;

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  Future<void> init() async {
    // IMPORTANT: You must create a transparent icon for notifications.
    // Place an image named 'ic_mapz_notification.png' in 'android/app/src/main/res/drawable/'.
    const AndroidInitializationSettings initializationSettingsAndroid =
    AndroidInitializationSettings('@drawable/ic_mapz_notification');

    const InitializationSettings initializationSettings =
    InitializationSettings(android: initializationSettingsAndroid);

    await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  }

  Future<void> showDiscoveryActiveNotification() async {
    const androidDetails = AndroidNotificationDetails(
      'road_discovery_channel',
      'Road Discovery',
      channelDescription: 'Notification shown when road discovery is active.',
      importance: Importance.low, // Low importance so it's less intrusive
      priority: Priority.low,
      ongoing: true, // Makes the notification persistent until cancelled
      autoCancel: false,
    );
    const notificationDetails = NotificationDetails(android: androidDetails);
    await flutterLocalNotificationsPlugin.show(
      _discoveryNotificationId,
      'Road Discovery Activated',
      'Tracking your journey to discover new roads.',
      notificationDetails,
    );
  }

  // --- NEW: Method to cancel the discovery notification ---
  Future<void> cancelDiscoveryActiveNotification() async {
    await flutterLocalNotificationsPlugin.cancel(_discoveryNotificationId);
  }

  Future<void> showLocationActiveNotification() async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'location_channel',
      'Location Tracking',
      channelDescription: 'Notification shown when location is being tracked.',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      playSound: false, // Make it silent
      enableVibration: false, // No vibration
      styleInformation: BigTextStyleInformation(
        'Just so you know, we\'re tracking your epic journey to map out all the cool roads. Don\'t worry, we won\'t tell anyone about that wrong turn you made.',
        htmlFormatBigText: true,
        contentTitle: '<b>Mapz is Tracking Your Adventure!</b>',
        htmlFormatContentTitle: true,
        summaryText: 'Happy Exploring!',
        htmlFormatSummaryText: true,
      ),
      color: Colors.blue,
    );
    const NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      0,
      'Mapz is Tracking Your Adventure!',
      'Mapping your epic journey...',
      platformChannelSpecifics,
      payload: 'location_payload',
    );
  }

  Future<void> showNavigationNotification({
    required String destination,
    required String eta,
    required String timeRemaining,
    required String nextTurn,
    required IconData maneuverIcon,
  }) async {
    final String bigText =
        'Time Remaining: <b>$timeRemaining</b><br>Next Turn: $nextTurn';
    final AndroidNotificationDetails androidPlatformChannelSpecifics =
    AndroidNotificationDetails(
      'navigation_channel',
      'Navigation Status',
      channelDescription: 'Shows current navigation information.',
      importance: Importance.high, // Keep high importance to show up, but make it silent
      priority: Priority.high,
      ongoing: true,
      autoCancel: false,
      playSound: false, // Make it silent
      enableVibration: false, // No vibration
      styleInformation: BigTextStyleInformation(
        bigText,
        htmlFormatBigText: true,
        contentTitle: '<b>Navigating to $destination</b> (ETA: $eta)',
        htmlFormatContentTitle: true,
      ),
      color: Colors.blue,
      // We can't directly show an IconData, but we can use native drawable resources.
      // This would require more native setup. For now, the app icon is used.
    );
    final NotificationDetails platformChannelSpecifics =
    NotificationDetails(android: androidPlatformChannelSpecifics);
    await flutterLocalNotificationsPlugin.show(
      1,
      'To: $destination ($eta)',
      'Next: $nextTurn',
      platformChannelSpecifics,
      payload: 'navigation_payload',
    );
  }


  Future<void> cancelLocationNotification() async {
    await flutterLocalNotificationsPlugin.cancel(0);
  }

  Future<void> cancelNavigationNotification() async {
    await flutterLocalNotificationsPlugin.cancel(1);
  }
  Future<void> requestPermissions() async {
    final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }
}