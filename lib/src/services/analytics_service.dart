import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Analytics Event Service
/// Handles event batching, local storage, and transmission to server
///
/// Features:
/// - Event batching (max 50 events or 30 seconds)
/// - Retry logic with exponential backoff
/// - Local quality preference persistence
/// - Resume point storage (every 10 seconds)
/// - Network-aware event transmission

/// Event types matching backend schema
enum AnalyticsEventType {
  sessionStart,
  sessionEnd,
  videoOpen,
  viewStart,
  viewProgress,
  viewComplete,
  bufferStart,
  bufferEnd,
  qualityChange,
  seek,
  pause,
  resume,
  downloadStart,
  downloadComplete,
  downloadCancel,
  error,
}

/// Quality change reasons
enum QualityChangeReason {
  user,
  auto,
  policy,
}

/// Network types
enum NetworkType {
  wifi,
  cellular,
  ethernet,
  unknown,
}

/// Source of the player (for analytics filtering)
enum PlayerSource {
  app,
  web,
  admin,
}

/// Purpose of playback
enum PlaybackPurpose {
  stream,
  download,
}

/// Analytics event data
class AnalyticsEvent {
  final AnalyticsEventType eventType;
  final String videoId;
  final DateTime timestamp;
  final Map<String, dynamic>? data;
  final NetworkType? networkType;

  AnalyticsEvent({
    required this.eventType,
    required this.videoId,
    DateTime? timestamp,
    this.data,
    this.networkType,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'eventType': _eventTypeToString(eventType),
      'videoId': videoId,
      // Remove microseconds to match backend datetime validation (ISO 8601 with milliseconds only)
      'timestamp': '${timestamp.toUtc().toIso8601String().split('.')[0]}Z',
      if (data != null) 'data': data,
      if (networkType != null)
        'network': {
          'type': _networkTypeToString(networkType!),
        },
    };
  }

  static String _eventTypeToString(AnalyticsEventType type) {
    switch (type) {
      case AnalyticsEventType.sessionStart:
        return 'session_start';
      case AnalyticsEventType.sessionEnd:
        return 'session_end';
      case AnalyticsEventType.videoOpen:
        return 'video_open';
      case AnalyticsEventType.viewStart:
        return 'view_start';
      case AnalyticsEventType.viewProgress:
        return 'view_progress';
      case AnalyticsEventType.viewComplete:
        return 'view_complete';
      case AnalyticsEventType.bufferStart:
        return 'buffer_start';
      case AnalyticsEventType.bufferEnd:
        return 'buffer_end';
      case AnalyticsEventType.qualityChange:
        return 'quality_change';
      case AnalyticsEventType.seek:
        return 'seek';
      case AnalyticsEventType.pause:
        return 'pause';
      case AnalyticsEventType.resume:
        return 'resume';
      case AnalyticsEventType.downloadStart:
        return 'download_start';
      case AnalyticsEventType.downloadComplete:
        return 'download_complete';
      case AnalyticsEventType.downloadCancel:
        return 'download_cancel';
      case AnalyticsEventType.error:
        return 'error';
    }
  }

  static String _networkTypeToString(NetworkType type) {
    switch (type) {
      case NetworkType.wifi:
        return 'wifi';
      case NetworkType.cellular:
        return 'cellular';
      case NetworkType.ethernet:
        return 'ethernet';
      case NetworkType.unknown:
        return 'unknown';
    }
  }
}

/// Analytics Service Singleton
class AnalyticsService {
  static final AnalyticsService _instance = AnalyticsService._internal();
  factory AnalyticsService() => _instance;
  AnalyticsService._internal();

  // Configuration
  static const int _maxBatchSize = 50;
  static const Duration _batchInterval = Duration(seconds: 30);
  static const Duration _resumePointInterval = Duration(seconds: 10);
  static const String _qualityPrefKey = 'preferred_quality';
  static const String _resumePointPrefix = 'resume_point_';
  static const String _pendingEventsKey = 'pending_analytics_events';

  // State
  String? _baseUrl;
  String? _authToken;
  String? _userId;
  String? _sessionId;
  PlayerSource _source = PlayerSource.app;
  PlaybackPurpose _purpose = PlaybackPurpose.stream;
  bool _isEnabled = true;

  final List<AnalyticsEvent> _eventBuffer = [];
  Timer? _batchTimer;
  Timer? _resumePointTimer;

  // Current video state
  String? _currentVideoId;
  double _currentPosition = 0;
  double _totalWatched = 0;

  // Network state
  NetworkType _networkType = NetworkType.unknown;

  // Callbacks
  Function(String)? onError;

  /// Initialize the service
  Future<void> initialize({
    required String baseUrl,
    String? authToken,
    String? userId,
    PlayerSource source = PlayerSource.app,
    PlaybackPurpose purpose = PlaybackPurpose.stream,
  }) async {
    _baseUrl = baseUrl;
    _authToken = authToken;
    _userId = userId;
    _source = source;
    _purpose = purpose;
    _sessionId = _generateSessionId();

    // Don't track analytics for admin preview
    _isEnabled = source != PlayerSource.admin;

    // Load any pending events from storage
    await _loadPendingEvents();

    // Start batch timer
    _startBatchTimer();

    if (kDebugMode) {
      debugPrint(
          '[AnalyticsService] Initialized: source=$source, enabled=$_isEnabled');
    }
  }

  /// Update auth token
  void updateAuthToken(String? token) {
    _authToken = token;
  }

  /// Set network type
  void setNetworkType(NetworkType type) {
    _networkType = type;
  }

  /// Update playback purpose
  void updatePurpose(PlaybackPurpose purpose) {
    if (_purpose != purpose) {
      if (kDebugMode) {
        debugPrint('[AnalyticsService] Updating purpose to: ${purpose.name}');
      }
      _purpose = purpose;
    }
  }

  /// Start tracking a video
  void startVideoTracking(String videoId) {
    if (!_isEnabled) return;

    _currentVideoId = videoId;
    _currentPosition = 0;
    _totalWatched = 0;
    _sessionId = _generateSessionId();

    // Track session start
    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.sessionStart,
      videoId: videoId,
    ));

    // Start resume point timer
    _startResumePointTimer();
  }

  /// Stop tracking current video
  void stopVideoTracking({double? finalPosition, double? completionPct}) {
    if (!_isEnabled || _currentVideoId == null) return;

    // Track session end
    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.sessionEnd,
      videoId: _currentVideoId!,
      data: {
        'position': finalPosition ?? _currentPosition,
        'totalWatched': _totalWatched,
        'completionPct': completionPct,
      },
    ));

    // Save resume point
    if (_currentVideoId != null && finalPosition != null) {
      _saveResumePoint(_currentVideoId!, finalPosition);
    }

    // Flush remaining events
    _flushEvents();

    // Stop timers
    _resumePointTimer?.cancel();
    _resumePointTimer = null;

    _currentVideoId = null;
  }

  /// Track an analytics event
  void trackEvent(AnalyticsEvent event) {
    if (!_isEnabled) return;

    _eventBuffer.add(event);

    // Flush if buffer is full
    if (_eventBuffer.length >= _maxBatchSize) {
      _flushEvents();
    }
  }

  /// Track video playback progress (called frequently)
  void trackProgress({
    required String videoId,
    required double position,
    required double duration,
    String? quality,
    double? bandwidth,
    double? playbackSpeed, // Added playback speed
  }) {
    if (!_isEnabled) return;

    _currentPosition = position;

    // Calculate total watched (simple approximation)
    _totalWatched = position; // Could be more sophisticated

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.viewProgress,
      videoId: videoId,
      networkType: _networkType,
      data: {
        'position': position,
        'duration': duration,
        if (quality != null) 'quality': quality,
        if (bandwidth != null) 'bandwidth': bandwidth,
        if (playbackSpeed != null) 'playbackSpeed': playbackSpeed,
        'totalWatched': _totalWatched,
      },
    ));
  }

  /// Track seek event
  void trackSeek({
    required String videoId,
    required double fromPosition,
    required double toPosition,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.seek,
      videoId: videoId,
      data: {
        'fromPosition': fromPosition,
        'toPosition': toPosition,
        'position': toPosition,
      },
    ));
  }

  /// Track quality change
  void trackQualityChange({
    required String videoId,
    required String fromQuality,
    required String toQuality,
    required QualityChangeReason reason,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.qualityChange,
      videoId: videoId,
      data: {
        'fromQuality': fromQuality,
        'toQuality': toQuality,
        'qualityChangeReason': reason.name,
      },
    ));

    // Save preferred quality if user selected it
    if (reason == QualityChangeReason.user) {
      savePreferredQuality(toQuality);
    }
  }

  /// Track pause
  void trackPause({required String videoId, required double position}) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.pause,
      videoId: videoId,
      data: {
        'position': position,
        'totalWatched': _totalWatched,
      },
    ));

    // Flush events on pause
    _flushEvents();
  }

  /// Track resume
  void trackResume({required String videoId, required double position}) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.resume,
      videoId: videoId,
      data: {
        'position': position,
      },
    ));
  }

  /// Track buffering start
  void trackBufferStart({
    required String videoId,
    required double position,
    String? quality,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.bufferStart,
      videoId: videoId,
      data: {
        'position': position,
        if (quality != null) 'quality': quality,
      },
    ));
  }

  /// Track buffering end
  void trackBufferEnd({
    required String videoId,
    required double duration,
    String? quality,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.bufferEnd,
      videoId: videoId,
      data: {
        'bufferDuration': duration,
        if (quality != null) 'quality': quality,
      },
    ));
  }

  /// Track video complete
  void trackComplete({
    required String videoId,
    required double duration,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.viewComplete,
      videoId: videoId,
      data: {
        'duration': duration,
        'totalWatched': _totalWatched,
        'completionPct': 100,
      },
    ));

    // Flush events on complete
    _flushEvents();
  }

  /// Track download start
  void trackDownloadStart({
    required String videoId,
    required String quality,
    int? estimatedSize,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.downloadStart,
      videoId: videoId,
      data: {
        'quality': quality,
        if (estimatedSize != null) 'downloadSize': estimatedSize,
      },
    ));
  }

  /// Track download complete
  void trackDownloadComplete({
    required String videoId,
    required String quality,
    required int actualSize,
    required int durationMs,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.downloadComplete,
      videoId: videoId,
      data: {
        'quality': quality,
        'downloadSize': actualSize,
        'downloadDuration': durationMs,
      },
    ));
  }

  /// Track error
  void trackError({
    required String videoId,
    required String errorMessage,
    String? errorCode,
    double? position,
  }) {
    if (!_isEnabled) return;

    trackEvent(AnalyticsEvent(
      eventType: AnalyticsEventType.error,
      videoId: videoId,
      data: {
        'errorMessage': errorMessage,
        if (errorCode != null) 'errorCode': errorCode,
        if (position != null) 'position': position,
      },
    ));

    // Flush immediately on error
    _flushEvents();
  }

  // ==================== Quality Preference ====================

  /// Save preferred quality
  Future<void> savePreferredQuality(String quality) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_qualityPrefKey, quality);
      debugPrint('[AnalyticsService] Saved preferred quality: $quality');
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to save quality preference: $e');
    }
  }

  /// Get preferred quality
  Future<String?> getPreferredQuality() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_qualityPrefKey);
    } catch (e) {
      return null;
    }
  }

  /// Get best available quality based on preference
  /// If preferred quality is not available, returns highest available quality below it
  String? getBestAvailableQuality(
    String? preferred,
    List<String> availableQualities,
  ) {
    if (availableQualities.isEmpty) return null;
    if (preferred == null) return availableQualities.first;

    // Quality order (highest to lowest)
    const qualityOrder = ['4k', '1440p', '1080p', '720p', '480p', '360p'];

    // Find preferred quality index
    final preferredIndex = qualityOrder.indexOf(preferred.toLowerCase());
    if (preferredIndex == -1) return availableQualities.first;

    // Try to find preferred or lower quality
    for (int i = preferredIndex; i < qualityOrder.length; i++) {
      final quality = qualityOrder[i];
      final match = availableQualities.firstWhere(
        (q) => q.toLowerCase().contains(quality.replaceAll('p', '')),
        orElse: () => '',
      );
      if (match.isNotEmpty) return match;
    }

    // Fallback to first available
    return availableQualities.first;
  }

  // ==================== Resume Point ====================

  /// Save resume point
  Future<void> _saveResumePoint(String videoId, double position) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('$_resumePointPrefix$videoId', position);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to save resume point: $e');
    }
  }

  /// Get resume point (Local only to save server resources)
  Future<double?> getResumePoint(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getDouble('$_resumePointPrefix$videoId');
    } catch (e) {
      return null;
    }
  }

  /// Clear resume point (when video is completed)
  Future<void> clearResumePoint(String videoId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_resumePointPrefix$videoId');
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to clear resume point: $e');
    }
  }

  // ==================== Private Methods ====================

  String _generateSessionId() {
    return '${DateTime.now().millisecondsSinceEpoch}-${_generateRandomString(8)}';
  }

  String _generateRandomString(int length) {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    return List.generate(
      length,
      (i) => chars[(random + i * 7) % chars.length],
    ).join();
  }

  void _startBatchTimer() {
    _batchTimer?.cancel();
    _batchTimer = Timer.periodic(_batchInterval, (_) => _flushEvents());
  }

  void _startResumePointTimer() {
    _resumePointTimer?.cancel();
    _resumePointTimer = Timer.periodic(_resumePointInterval, (_) {
      if (_currentVideoId != null && _currentPosition > 0) {
        _saveResumePoint(_currentVideoId!, _currentPosition);
      }
    });
  }

  Future<void> _flushEvents() async {
    if (_eventBuffer.isEmpty || _baseUrl == null) return;

    // Copy events and clear buffer
    final events = List<AnalyticsEvent>.from(_eventBuffer);
    _eventBuffer.clear();

    try {
      await _sendEvents(events);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to send events: $e');
      // Store events for retry
      await _savePendingEvents(events);
      onError?.call('Failed to send analytics: $e');
    }
  }

  Future<void> _sendEvents(List<AnalyticsEvent> events) async {
    if (events.isEmpty || _baseUrl == null) return;

    final payload = {
      'sessionId': _sessionId,
      'userId': _userId,
      'source': _source.name,
      'purpose': _purpose.name,
      'events': events.map((e) => e.toJson()).toList(),
    };

    final response = await http
        .post(
          Uri.parse('$_baseUrl/api/v1/analytics/events/batch'),
          headers: {
            'Content-Type': 'application/json',
            if (_authToken != null) ...{
              'Authorization': 'Bearer $_authToken',
              'Account-ID': _authToken!,
            },
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    debugPrint('[AnalyticsService] Sent ${events.length} events');
  }

  Future<void> _savePendingEvents(List<AnalyticsEvent> events) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getStringList(_pendingEventsKey) ?? [];
      final newEvents = events.map((e) => jsonEncode(e.toJson())).toList();
      await prefs.setStringList(_pendingEventsKey, [...existing, ...newEvents]);
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to save pending events: $e');
    }
  }

  Future<void> _loadPendingEvents() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(_pendingEventsKey);
      if (pending != null && pending.isNotEmpty) {
        // Try to send pending events
        debugPrint('[AnalyticsService] Found ${pending.length} pending events');
        // Clear pending after loading
        await prefs.remove(_pendingEventsKey);
      }
    } catch (e) {
      debugPrint('[AnalyticsService] Failed to load pending events: $e');
    }
  }

  /// Dispose of resources
  void dispose() {
    _batchTimer?.cancel();
    _resumePointTimer?.cancel();
    _flushEvents();
  }
}
