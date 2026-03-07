import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';
import 'app_logger.dart';

/// Manages FCM token registration, foreground notifications, and cleanup.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _logger = AppLogger.instance;
  late final _messaging = FirebaseMessaging.instance;
  late final _localNotifications = FlutterLocalNotificationsPlugin();

  String? _currentToken;
  ApiService? _apiService;

  /// Callback invoked when user taps a notification with a task_id.
  void Function(String taskId)? onNotificationTap;

  /// Initialize notifications: request permission, register token, set up listeners.
  /// Fails silently if Firebase is not initialized (e.g. in tests).
  Future<void> initialize(ApiService apiService) async {
    _apiService = apiService;

    try {
      await _initializeInternal();
    } catch (e) {
      _logger.warning('notification.init_failed',
          logger: 'NotificationService', data: {'error': e.toString()});
    }
  }

  Future<void> _initializeInternal() async {
    // Request permission (iOS shows prompt, Android 13+ needs runtime permission)
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      _logger.info('notification.permission_denied', logger: 'NotificationService');
      return;
    }

    // Initialize local notifications for foreground display
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );

    // Get and register token
    _currentToken = await _messaging.getToken();
    if (_currentToken != null) {
      await _registerToken(_currentToken!);
    }

    // Listen for token refresh
    _messaging.onTokenRefresh.listen((newToken) async {
      _currentToken = newToken;
      await _registerToken(newToken);
    });

    // Foreground message handler — show local notification
    FirebaseMessaging.onMessage.listen(_showLocalNotification);

    // Handle notification tap when app is in background
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // Handle notification that launched the app from terminated state
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      _handleNotificationTap(initialMessage);
    }

    _logger.info('notification.initialized', logger: 'NotificationService');
  }


  /// Unregister token from backend (call before sign-out).
  Future<void> unregister() async {
    if (_currentToken != null && _apiService != null) {
      try {
        await _apiService!.unregisterFcmToken(_currentToken!);
        _logger.info('notification.unregistered', logger: 'NotificationService');
      } catch (e) {
        _logger.warning('notification.unregister_failed',
            logger: 'NotificationService', data: {'error': e.toString()});
      }
    }
    _currentToken = null;
  }

  Future<void> _registerToken(String token) async {
    if (_apiService == null) return;
    try {
      final platform = Platform.isIOS ? 'ios' : 'android';
      final timezone = DateTime.now().timeZoneName;
      await _apiService!.registerFcmToken(token, platform, timezone);
      _logger.info('notification.token_registered',
          logger: 'NotificationService', data: {'platform': platform});
    } catch (e) {
      _logger.warning('notification.register_failed',
          logger: 'NotificationService', data: {'error': e.toString()});
    }
  }

  void _handleNotificationTap(RemoteMessage message) {
    final taskId = message.data['task_id'] as String?;
    if (taskId != null && onNotificationTap != null) {
      _logger.info('notification.tap', logger: 'NotificationService', data: {'task_id': taskId});
      onNotificationTap!(taskId);
    }
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'task_reminders',
      'Task Reminders',
      channelDescription: 'Notifications for upcoming task due dates',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
    );
  }
}
