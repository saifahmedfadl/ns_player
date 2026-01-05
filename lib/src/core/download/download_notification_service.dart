import 'dart:async';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

import 'hls_download_service.dart';

/// Service for managing download notifications with pause/resume/cancel controls
class DownloadNotificationService {
  static final DownloadNotificationService _instance =
      DownloadNotificationService._();
  static DownloadNotificationService get instance => _instance;

  DownloadNotificationService._();

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  final Map<String, int> _notificationIds = {};
  int _nextNotificationId = 1000;

  StreamSubscription<HlsDownloadProgress>? _progressSubscription;

  // Cache for throttling updates
  final Map<String, int> _lastNotifiedProgress = {};
  final Map<String, DateTime> _lastUpdateTime = {};
  final Map<String, HlsDownloadStatus> _lastStatus = {};

  /// Channel ID for download notifications
  static const String _channelId = 'ns_player_downloads';
  static const String _channelName = 'Video Downloads';
  static const String _channelDescription =
      'Notifications for video download progress';

  /// Action IDs
  static const String actionPause = 'pause_download';
  static const String actionResume = 'resume_download';
  static const String actionCancel = 'cancel_download';

  /// Initialize the notification service
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Request notification permission on Android 13+
    if (Platform.isAndroid) {
      final status = await Permission.notification.status;
      if (!status.isGranted) {
        await Permission.notification.request();
      }
    }

    // Initialize notifications
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _onNotificationAction,
      onDidReceiveBackgroundNotificationResponse:
          _onBackgroundNotificationAction,
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      final androidPlugin =
          _notifications.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();

      await androidPlugin?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.low,
          showBadge: false,
          playSound: false,
          enableVibration: false,
        ),
      );
    }

    // Listen to download progress updates
    _progressSubscription = HlsDownloadService.progressStream.listen(
      _onDownloadProgress,
    );

    _isInitialized = true;
  }

  /// Handle notification actions
  void _onNotificationAction(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final parts = payload.split('|');
    if (parts.length < 2) return;

    final videoId = parts[0];
    final quality = parts[1];

    switch (response.actionId) {
      case actionPause:
        HlsDownloadService.pauseDownload(videoId, quality);
        break;
      case actionResume:
        // Resume requires the M3U8Data, which we don't have here
        // The UI should handle resume with full data
        break;
      case actionCancel:
        HlsDownloadService.cancelDownload(videoId, quality);
        _dismissNotification(videoId, quality);
        break;
    }
  }

  /// Show or update download progress notification
  Future<void> showDownloadProgress({
    required String videoId,
    required String quality,
    required int downloadedSegments,
    required int totalSegments,
    required double speed,
    required HlsDownloadStatus status,
    String? title,
  }) async {
    if (!_isInitialized) await initialize();

    final key = '${videoId}_$quality';
    final currentStatus = status;
    final lastStatus = _lastStatus[key];

    final progress = totalSegments > 0
        ? ((downloadedSegments / totalSegments) * 100).round()
        : 0;

    final lastProgress = _lastNotifiedProgress[key] ?? -1;
    final lastUpdate =
        _lastUpdateTime[key] ?? DateTime.fromMillisecondsSinceEpoch(0);
    final now = DateTime.now();

    // Throttling: Only update if status changed, or significant progress made, or enough time passed
    bool shouldUpdate = false;
    if (currentStatus != lastStatus) {
      shouldUpdate = true;
    } else if (currentStatus == HlsDownloadStatus.downloading) {
      // Only update every 2 seconds OR if progress jumped by 2%
      if (now.difference(lastUpdate).inSeconds >= 2 ||
          (progress - lastProgress).abs() >= 2) {
        shouldUpdate = true;
      }
    } else {
      // For other statuses (completed, failed, etc.), always update
      shouldUpdate = true;
    }

    if (!shouldUpdate) return;

    // Save state for next check
    _lastStatus[key] = currentStatus;
    _lastNotifiedProgress[key] = progress;
    _lastUpdateTime[key] = now;

    final notificationId = _getNotificationId(videoId, quality);

    final speedText = _formatSpeed(speed);
    //percentage
    final progressText = '$progress%';
    // final progressText = '$downloadedSegments / $totalSegments segments';

    String statusText;
    List<AndroidNotificationAction> actions;

    switch (status) {
      case HlsDownloadStatus.downloading:
        statusText = '$progressText • $speedText';
        actions = [
          const AndroidNotificationAction(
            actionPause,
            'Pause',
            showsUserInterface: false,
            cancelNotification: false,
          ),
          const AndroidNotificationAction(
            actionCancel,
            'Cancel',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];
        break;
      case HlsDownloadStatus.paused:
        statusText = 'Paused • $progressText';
        actions = [
          const AndroidNotificationAction(
            actionResume,
            'Resume',
            showsUserInterface: true,
            cancelNotification: false,
          ),
          const AndroidNotificationAction(
            actionCancel,
            'Cancel',
            showsUserInterface: false,
            cancelNotification: true,
          ),
        ];
        break;
      case HlsDownloadStatus.completed:
        statusText = 'Download complete';
        actions = [];
        // Auto-dismiss after a delay
        Future.delayed(const Duration(seconds: 3), () {
          _dismissNotification(videoId, quality);
        });
        break;
      case HlsDownloadStatus.failed:
        statusText = 'Download failed';
        actions = [];
        break;
      case HlsDownloadStatus.cancelled:
        _dismissNotification(videoId, quality);
        return;
      default:
        statusText = 'Preparing...';
        actions = [];
    }

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      showWhen: false,
      ongoing: status == HlsDownloadStatus.downloading,
      autoCancel: status == HlsDownloadStatus.completed,
      progress: progress,
      maxProgress: 100,
      showProgress: status == HlsDownloadStatus.downloading ||
          status == HlsDownloadStatus.paused,
      indeterminate: status == HlsDownloadStatus.pending,
      actions: actions,
      category: AndroidNotificationCategory.progress,
      visibility: NotificationVisibility.public,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: status == HlsDownloadStatus.completed ||
          status == HlsDownloadStatus.failed,
      presentBadge: false,
      presentSound: false,
      subtitle: statusText,
      interruptionLevel: (status == HlsDownloadStatus.downloading ||
              status == HlsDownloadStatus.paused)
          ? InterruptionLevel.passive
          : InterruptionLevel.active,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      id: notificationId,
      title: title ?? 'Downloading video ($quality)',
      body: statusText,
      notificationDetails: details,
      payload: '$videoId|$quality',
    );
  }

  /// Handle download progress updates from the stream
  void _onDownloadProgress(HlsDownloadProgress progress) {
    showDownloadProgress(
      videoId: progress.videoId,
      quality: progress.quality,
      downloadedSegments: progress.downloadedSegments,
      totalSegments: progress.totalSegments,
      speed: progress.speed,
      status: progress.status,
    );
  }

  /// Dismiss a download notification
  Future<void> _dismissNotification(String videoId, String quality) async {
    final key = '${videoId}_$quality';
    final notificationId = _notificationIds[key];
    if (notificationId != null) {
      await _notifications.cancel(id: notificationId);
      _notificationIds.remove(key);
    }
  }

  /// Get or create notification ID for a download
  int _getNotificationId(String videoId, String quality) {
    final key = '${videoId}_$quality';
    return _notificationIds.putIfAbsent(key, () => _nextNotificationId++);
  }

  /// Format download speed
  String _formatSpeed(double bytesPerSecond) {
    if (bytesPerSecond < 1024) {
      return '${bytesPerSecond.toStringAsFixed(0)} B/s';
    } else if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    } else {
      return '${(bytesPerSecond / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
  }

  /// Cancel all notifications
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    _notificationIds.clear();
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _progressSubscription?.cancel();
    await cancelAll();
  }
}

/// Background notification action handler
@pragma('vm:entry-point')
void _onBackgroundNotificationAction(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return;

  final parts = payload.split('|');
  if (parts.length < 2) return;

  final videoId = parts[0];
  final quality = parts[1];

  switch (response.actionId) {
    case DownloadNotificationService.actionPause:
      HlsDownloadService.pauseDownload(videoId, quality);
      break;
    case DownloadNotificationService.actionCancel:
      HlsDownloadService.cancelDownload(videoId, quality);
      break;
  }
}
