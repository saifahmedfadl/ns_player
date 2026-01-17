import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'buffer_control.dart';
import 'core/download/hls_download_service.dart';
import 'core/playback/local_hls_server.dart';
import 'model/m3u8.dart';
import 'services/analytics_service.dart';
import 'ui/fullscreen/fullscreen_player.dart';
import 'ui/widgets/double_tap_seek.dart';
import 'ui/widgets/loading_animation.dart';
import 'ui/widgets/settings_bottom_sheet.dart';
import 'ui/widgets/video_controls.dart';

/// Analytics configuration for the player
class AnalyticsConfig {
  /// Base URL for the analytics API
  final String baseUrl;

  /// Auth token for API requests
  final String? authToken;

  /// User ID for tracking individual student analytics
  final String? userId;

  /// Source of the player (app, web, or admin)
  /// Admin sources are ignored for analytics
  final PlayerSource source;

  const AnalyticsConfig({
    this.baseUrl = 'https://api.nexwavetec.com/api/v1',
    this.authToken,
    this.userId,
    this.source = PlayerSource.app,
  });
}

/// Modern video player widget with YouTube-style controls,
/// secure video downloads, and fullscreen support.
class NsPlayer extends StatefulWidget {
  /// Video source URL (supports HLS .m3u8, MP4, MKV, WEBM)
  final String url;

  /// Pre-parsed qualities from API (backend-driven approach)
  /// If provided, the player will NOT parse the manifest for qualities.
  /// This is the recommended approach for accurate file sizes and metadata.
  final List<M3U8Data>? qualities;

  /// Total video duration in seconds (from API)
  final double? totalDuration;

  /// Video aspect ratio. Default is 16:9
  final double aspectRatio;

  /// HTTP headers for video requests
  final Map<String, String>? headers;

  /// Auto-play video after initialization. Default is true
  final bool autoPlay;

  /// Callback when video initialization completes
  final void Function(VideoPlayerController controller)? onVideoInitCompleted;

  /// Callback when fullscreen mode changes
  final void Function(bool isFullScreen)? onFullScreenChanged;

  /// Callback when video starts playing
  final void Function(String videoType)? onPlayingVideo;

  /// Callback when play/pause button is tapped
  final void Function(bool isPlaying)? onPlayButtonTap;

  /// Closed caption file for the video
  final Future<ClosedCaptionFile>? closedCaptionFile;

  /// Additional video player options
  final VideoPlayerOptions? videoPlayerOptions;

  /// Primary color for loading animation and controls
  final Color? primaryColor;

  /// Analytics configuration
  /// If not provided, analytics will be disabled
  final AnalyticsConfig? analyticsConfig;

  /// Callback for video position updates
  /// Called periodically with duration and position
  final void Function(Duration duration, Duration position)? addListener;

  const NsPlayer({
    super.key,
    required this.url,
    this.qualities,
    this.totalDuration,
    this.aspectRatio = 16 / 9,
    this.headers,
    this.autoPlay = true,
    this.onVideoInitCompleted,
    this.onFullScreenChanged,
    this.onPlayingVideo,
    this.onPlayButtonTap,
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.primaryColor,
    this.analyticsConfig,
    this.addListener,
  });

  @override
  State<NsPlayer> createState() => _NsPlayerState();
}

class _NsPlayerState extends State<NsPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _isFullScreen = false;
  bool _isLooping = false;
  double _playbackSpeed = 1.0;
  String _currentQuality = 'Auto';
  Duration? _lastPosition;
  int _initCounter = 0; // Prevent race conditions during initialization

  // Rate limiting protection to prevent HTTP 429 errors
  int _retryCount = 0;
  static const int _maxAutoRetries =
      2; // Max automatic retries before requiring manual retry
  DateTime? _lastErrorTime;
  static const Duration _minRetryInterval =
      Duration(seconds: 3); // Minimum time between retries

  List<M3U8Data> _qualities = [];
  final LocalHlsPlaybackManager _hlsPlaybackManager =
      LocalHlsPlaybackManager.instance;

  // Analytics
  final AnalyticsService _analyticsService = AnalyticsService();
  Timer? _progressTimer;
  double _lastReportedPosition = 0.0;
  bool _isBuffering = false;
  DateTime? _bufferStartTime;
  DateTime? _lastListenerUpdateTime;

  /// Unique identifier for the video (used for download management)
  /// If not provided, a hash of the URL will be used
  // String? videoId;

  String get _videoId {
    return _extractVideoIdFromUrl(widget.url) ?? 'Unknown';
  }

  /// Extract MongoDB ObjectId from video URL
  /// URL format: https://videostream.nexwavetec.com/api/v1/videos/{videoId}/stream/master.m3u8
  String? _extractVideoIdFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final segments = uri.pathSegments;

      // Find "videos" segment and get the next one
      final videosIndex = segments.indexOf('videos');
      if (videosIndex != -1 && videosIndex + 1 < segments.length) {
        final videoId = segments[videosIndex + 1];
        // Validate it looks like a MongoDB ObjectId (24 hex characters)
        // Must contain at least one letter (a-f) to be valid hex, not just digits
        if (videoId.length == 24 &&
            RegExp(r'^[a-f0-9]{24}$').hasMatch(videoId) &&
            RegExp(r'[a-f]').hasMatch(videoId)) {
          if (kDebugMode) {
            debugPrint(
                '[Analytics] Extracted videoId: $videoId from URL: $url');
          }
          return videoId;
        }
      }

      if (kDebugMode) {
        debugPrint('[Analytics] Failed to extract videoId from URL: $url');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[Analytics] Error extracting videoId: $e');
      }
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (kDebugMode) {
      print('Initial NsPlayer qualities data:');
      if (widget.qualities != null) {
        for (var q in widget.qualities!) {
          print(q.toString());
        }
      } else {
        print('No qualities provided to widget');
      }
    }
    _initializeAnalytics();
    _initializePlayer();
  }

  Future<void> _initializeAnalytics() async {
    if (widget.analyticsConfig == null) return;

    final config = widget.analyticsConfig!;
    await _analyticsService.initialize(
      baseUrl: config.baseUrl,
      authToken: config.authToken,
      userId: config.userId, // ✅ إضافة userId
      source: config.source,
      purpose: PlaybackPurpose.stream, // Default to stream initially
    );

    // Check for saved preferred quality and apply it
    final preferredQuality = await _analyticsService.getPreferredQuality();
    if (preferredQuality != null && mounted) {
      // Will be applied when qualities are loaded
      if (kDebugMode) {
        print('[NsPlayer] Loaded preferred quality: $preferredQuality');
      }
    }
  }

  @override
  void didUpdateWidget(NsPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      if (kDebugMode) {
        print('NsPlayer: Video changed. Resetting player...');
      }
      _handleVideoChange();
    }
  }

  Future<void> _handleVideoChange() async {
    _disposeController();
    await _hlsPlaybackManager.stopPlayback();

    if (mounted) {
      setState(() {
        _currentQuality = 'Auto';
        _lastPosition = null;
        _isInitialized = false;
        _qualities = []; // Clear old qualities
        _initCounter++; // Increment counter to invalidate previous init attempts
        // Reset rate limiting state for new video
        _retryCount = 0;
        _lastErrorTime = null;
      });

      // Small delay to ensure resources are freed and OS file system catches up
      await Future.delayed(const Duration(milliseconds: 500));
      if (mounted) {
        _initializePlayer();
      }
    }
  }

  @override
  void dispose() {
    _stopAnalyticsTracking();
    _disposeController();
    _hlsPlaybackManager.stopPlayback();
    super.dispose();
  }

  void _stopAnalyticsTracking() {
    _progressTimer?.cancel();
    _progressTimer = null;

    // Stop tracking with final position
    final position = _controller?.value.position.inSeconds.toDouble() ?? 0.0;
    final duration = _controller?.value.duration.inSeconds.toDouble() ?? 0.0;
    final completionPct = duration > 0 ? (position / duration) * 100.0 : 0.0;

    _analyticsService.stopVideoTracking(
      finalPosition: position,
      completionPct: completionPct,
    );
  }

  void _startAnalyticsTracking() {
    if (widget.analyticsConfig == null) return;

    // Start tracking this video
    _analyticsService.startVideoTracking(_videoId);
    _lastReportedPosition = 0;

    // Start progress timer (every 10 seconds)
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _reportProgress();
    });
  }

  void _reportProgress() {
    if (_controller == null || !_controller!.value.isPlaying) return;

    final position = _controller!.value.position.inSeconds.toDouble();
    final duration = _controller!.value.duration.inSeconds.toDouble();

    // Only report if position changed significantly (more than 1 second)
    if ((position - _lastReportedPosition).abs() > 1) {
      _analyticsService.trackProgress(
        videoId: _videoId,
        position: position,
        duration: duration,
        quality: _currentQuality,
        playbackSpeed: _playbackSpeed, // Pass current playback speed
      );
      _lastReportedPosition = position;
    }
  }

  Future<void> _applyPreferredQuality() async {
    if (_qualities.isEmpty) return;

    final preferred = await _analyticsService.getPreferredQuality();
    if (preferred == null) return;

    // Find matching quality or best available
    final availableQualities = _qualities
        .where((q) => q.dataQuality != 'Auto')
        .map((q) => q.dataQuality!)
        .toList();

    final bestQuality = _analyticsService.getBestAvailableQuality(
        preferred, availableQualities);

    if (bestQuality != null && bestQuality != _currentQuality) {
      final quality = _qualities.firstWhere(
        (q) => q.dataQuality == bestQuality,
        orElse: () => _qualities.first,
      );

      if (quality.dataQuality != 'Auto') {
        if (kDebugMode) {
          print('[NsPlayer] Applying preferred quality: $bestQuality');
        }
        await _onQualitySelected(quality);
      }
    }
  }

  void _disposeController() {
    _controller?.removeListener(_videoListener);
    _controller?.dispose();
    _controller = null;
  }

  Future<void> _initializePlayer({bool isManualRetry = false}) async {
    final currentInitId = ++_initCounter;

    // Rate limiting protection to prevent HTTP 429 errors
    if (!isManualRetry) {
      // Check if we've exceeded automatic retry limit
      if (_retryCount >= _maxAutoRetries) {
        if (kDebugMode) {
          print(
              'NsPlayer [Init #$currentInitId]: Max auto-retries reached ($_maxAutoRetries). Waiting for manual retry.');
        }
        setState(() {
          _hasError = true;
        });
        return;
      }

      // Enforce minimum interval between retries
      if (_lastErrorTime != null) {
        final timeSinceLastError = DateTime.now().difference(_lastErrorTime!);
        if (timeSinceLastError < _minRetryInterval) {
          final waitTime = _minRetryInterval - timeSinceLastError;
          if (kDebugMode) {
            print(
                'NsPlayer [Init #$currentInitId]: Rate limiting - waiting ${waitTime.inMilliseconds}ms before retry');
          }
          await Future.delayed(waitTime);
        }
      }
    } else {
      // Manual retry resets the counter
      _retryCount = 0;
    }

    setState(() {
      _isInitialized = false;
      _hasError = false;
    });

    try {
      // Apply buffer control settings before creating video player
      // This reduces bandwidth usage by limiting how much video is buffered
      await NsBufferControl.initialize(BufferPreset.low);

      if (kDebugMode) {
        print(
            'NsPlayer [Init #$currentInitId]: Starting... (retry: $_retryCount)');
        print('NsPlayer [Init #$currentInitId]: Video ID: $_videoId');
        print('NsPlayer [Init #$currentInitId]: URL: ${widget.url}');
        print(
            'NsPlayer [Init #$currentInitId]: Buffer config: ${NsBufferControl.currentConfig}');
      }
      // Determine video type and check for downloaded version
      final videoType = _getVideoType(widget.url);
      widget.onPlayingVideo?.call(videoType);

      String? playingQuality;

      // Check network connectivity
      final connectivity = Connectivity();
      final connectivityResult = await connectivity.checkConnectivity();
      final hasNetwork = !connectivityResult.contains(ConnectivityResult.none);

      if (currentInitId != _initCounter) {
        return; // Abort if a newer init started
      }

      // Check if video is downloaded for current quality (HLS)
      String? hlsPlaybackUrl;

      // If current quality is "Auto", first check if ANY quality is downloaded
      // and prefer playing that instead of streaming
      if (_currentQuality == 'Auto') {
        final downloadedQuality = await _findAnyDownloadedQuality();
        if (downloadedQuality != null) {
          try {
            hlsPlaybackUrl = await _hlsPlaybackManager.getPlaybackUrl(
              videoId: _videoId,
              quality: downloadedQuality,
            );
            playingQuality = downloadedQuality;
            _currentQuality = downloadedQuality; // Switch to downloaded quality
            if (kDebugMode) {
              print(
                  'Auto-selected downloaded quality ($downloadedQuality): $hlsPlaybackUrl');
            }
          } catch (e) {
            if (kDebugMode) {
              print(
                  'Error getting HLS playback URL for $downloadedQuality: $e');
            }
            hlsPlaybackUrl = null;
          }
        }
      } else {
        // Check if the selected quality is downloaded
        final isDownloaded = await HlsDownloadService.isDownloaded(
          _videoId,
          _currentQuality,
        );
        if (isDownloaded) {
          try {
            hlsPlaybackUrl = await _hlsPlaybackManager.getPlaybackUrl(
              videoId: _videoId,
              quality: _currentQuality,
            );
            playingQuality = _currentQuality;
            if (kDebugMode) {
              print(
                  'Playing downloaded HLS ($_currentQuality): $hlsPlaybackUrl');
            }
          } catch (e) {
            if (kDebugMode) {
              print('Error getting HLS playback URL: $e');
            }
            hlsPlaybackUrl = null;
          }
        }
      }

      // If no network and still no local file, try to find ANY downloaded quality
      if (!hasNetwork && hlsPlaybackUrl == null) {
        if (kDebugMode) {
          print('No network - searching for any downloaded quality...');
        }
        final downloadedQuality = await _findAnyDownloadedQuality();
        if (downloadedQuality != null) {
          try {
            hlsPlaybackUrl = await _hlsPlaybackManager.getPlaybackUrl(
              videoId: _videoId,
              quality: downloadedQuality,
            );
            playingQuality = downloadedQuality;
            _currentQuality = downloadedQuality;
            if (kDebugMode) {
              print(
                  'Found downloaded quality ($downloadedQuality): $hlsPlaybackUrl');
            }
          } catch (e) {
            if (kDebugMode) {
              print(
                  'Error getting HLS playback URL for $downloadedQuality: $e');
            }
          }
        }
      }

      // Get resume point from server or local storage
      if (widget.analyticsConfig != null && _lastPosition == null) {
        final resumePoint = await _analyticsService.getResumePoint(_videoId);
        if (resumePoint != null && resumePoint > 5) {
          // Only resume if more than 5 seconds in
          _lastPosition = Duration(seconds: resumePoint.toInt());
          if (kDebugMode) {
            print('NsPlayer: Found resume point at $resumePoint seconds');
          }
        }
      }

      // Initialize controller
      if (hlsPlaybackUrl != null) {
        if (currentInitId != _initCounter) {
          return;
        }

        // iOS: Use networkUrl for local HTTP server (AVPlayer doesn't support local HLS files)
        // Android: Use file controller for temp files
        if (Platform.isIOS && hlsPlaybackUrl.startsWith('http://127.0.0.1')) {
          // iOS local HTTP server - use networkUrl
          if (kDebugMode) {
            print(
                'NsPlayer [Init #$currentInitId]: iOS - Initializing from local HTTP server: $hlsPlaybackUrl');
          }
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(hlsPlaybackUrl),
            formatHint: VideoFormat.hls,
            closedCaptionFile: widget.closedCaptionFile,
            videoPlayerOptions: widget.videoPlayerOptions,
          );
        } else {
          // Android: Play from local temp files
          if (kDebugMode) {
            print(
                'NsPlayer [Init #$currentInitId]: Initializing from local file: $hlsPlaybackUrl');
          }
          _controller = VideoPlayerController.file(
            File(hlsPlaybackUrl),
            closedCaptionFile: widget.closedCaptionFile,
            videoPlayerOptions: widget.videoPlayerOptions,
          );
        }
        // Update current quality to match what we're playing
        if (playingQuality != null) {
          _currentQuality = playingQuality;
        }
      } else if (hasNetwork) {
        if (currentInitId != _initCounter) {
          return;
        }

        if (kDebugMode) {
          print(
              'NsPlayer [Init #$currentInitId]: Initializing from network: ${widget.url}');
        }
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(widget.url),
          httpHeaders: widget.headers ?? const {},
          formatHint: _getVideoFormat(videoType),
          closedCaptionFile: widget.closedCaptionFile,
          videoPlayerOptions: widget.videoPlayerOptions,
        );
      } else {
        throw Exception(
            'No network connection and no downloaded video available');
      }

      if (currentInitId != _initCounter) {
        _disposeController();
        return;
      }

      await _controller!.initialize();

      // Update analytics purpose based on whether we're playing a local file or network URL
      if (widget.analyticsConfig != null) {
        final isLocalPlayback = hlsPlaybackUrl != null;
        _analyticsService.updatePurpose(
          isLocalPlayback ? PlaybackPurpose.download : PlaybackPurpose.stream,
        );
      }

      if (currentInitId != _initCounter) {
        _disposeController();
        return;
      }

      _controller!.addListener(_videoListener);

      // Restore position if switching quality
      if (_lastPosition != null) {
        await _controller!.seekTo(_lastPosition!);
        _lastPosition = null;
      }

      // Apply settings
      await _controller!.setLooping(_isLooping);
      await _controller!.setPlaybackSpeed(_playbackSpeed);

      if (widget.autoPlay) {
        await _controller!.play();
      }

      setState(() {
        _isInitialized = true;
      });

      widget.onVideoInitCompleted?.call(_controller!);

      // Start analytics tracking
      _startAnalyticsTracking();

      // Use API-provided qualities if available (backend-driven approach)
      // Otherwise, fall back to parsing the manifest (legacy approach)
      if (widget.qualities != null && widget.qualities!.isNotEmpty) {
        // Backend-driven: Use pre-parsed qualities from API
        setState(() {
          _qualities = [
            M3U8Data(dataQuality: 'Auto', dataURL: widget.url),
            ...widget.qualities!,
          ];
        });
        if (kDebugMode) {
          print('Using ${widget.qualities!.length} qualities from API');
        }

        // Apply preferred quality if saved
        _applyPreferredQuality();
      } else if (videoType == 'HLS') {
        // Try to fetch quality sizes from backend API first
        await _fetchQualitySizesFromApi();

        // If no quality sizes from API, fall back to parsing manifest
        if (_qualities.isEmpty || _qualities.length == 1) {
          _fetchQualities(widget.url);
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Video initialization error: $e');
      }

      // Track error for rate limiting
      _lastErrorTime = DateTime.now();
      _retryCount++;

      // Check if this is a rate limiting error (HTTP 429)
      final isRateLimitError = e.toString().contains('429') ||
          e.toString().contains('rate') ||
          e.toString().contains('-16845');

      if (isRateLimitError) {
        if (kDebugMode) {
          print('NsPlayer: Rate limit detected. Retry count: $_retryCount');
        }

        // Auto-retry with exponential backoff for rate limit errors (max 3 retries)
        if (_retryCount <= 3) {
          final waitSeconds = 3 * _retryCount; // 3s, 6s, 9s
          if (kDebugMode) {
            print('NsPlayer: Waiting ${waitSeconds}s before retry...');
          }
          await Future.delayed(Duration(seconds: waitSeconds));
          if (mounted) {
            _initializePlayer();
          }
          return;
        }
      }

      setState(() {
        _hasError = true;
      });
    }
  }

  String _getVideoType(String url) {
    final uri = Uri.parse(url);
    final path = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '';

    if (path.endsWith('.m3u8')) return 'HLS';
    if (path.endsWith('.mp4')) return 'MP4';
    if (path.endsWith('.mkv')) return 'MKV';
    if (path.endsWith('.webm')) return 'WEBM';
    return 'HLS'; // Default to HLS
  }

  /// Find any downloaded quality for this video
  Future<String?> _findAnyDownloadedQuality() async {
    try {
      // Check common quality names
      final commonQualities = [
        '1920x1080',
        '1280x720',
        '854x480',
        '640x360',
        '426x240',
        '1080p',
        '720p',
        '480p',
        '360p',
        '240p',
      ];

      for (final quality in commonQualities) {
        final isDownloaded = await HlsDownloadService.isDownloaded(
          _videoId,
          quality,
          url: widget.url,
        );
        if (isDownloaded) {
          return quality;
        }
      }

      // Also check qualities from the list if available
      for (final q in _qualities) {
        if (q.dataQuality != null && q.dataQuality != 'Auto') {
          final isDownloaded = await HlsDownloadService.isDownloaded(
            _videoId,
            q.dataQuality!,
            url: widget.url,
          );
          if (isDownloaded) {
            return q.dataQuality;
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error finding downloaded quality: $e');
      }
    }
    return null;
  }

  VideoFormat? _getVideoFormat(String type) {
    switch (type) {
      case 'HLS':
        return VideoFormat.hls;
      case 'MKV':
        return VideoFormat.dash;
      default:
        return VideoFormat.other;
    }
  }

  void _videoListener() {
    if (_controller == null) return;

    final value = _controller!.value;
    final now = DateTime.now();

    // Throttling: Only execute heavy logic and UI updates every 2 seconds
    // to reduce CPU usage. Critical events (buffering start/end, completion)
    // are still processed immediately.
    final bool isCriticalEvent = (value.isBuffering != _isBuffering) ||
        (value.position >= value.duration &&
            value.duration.inSeconds > 0 &&
            !value.isPlaying);

    if (_lastListenerUpdateTime != null &&
        now.difference(_lastListenerUpdateTime!) < const Duration(seconds: 4) &&
        !isCriticalEvent) {
      return;
    }
    _lastListenerUpdateTime = now;

    // Manage wakelock
    if (value.isPlaying) {
      WakelockPlus.enable();
    } else {
      WakelockPlus.disable();
    }

    // Track buffering events
    if (value.isBuffering && !_isBuffering) {
      _isBuffering = true;
      _bufferStartTime = DateTime.now();
      _analyticsService.trackBufferStart(
        videoId: _videoId,
        position: value.position.inSeconds.toDouble(),
        quality: _currentQuality,
      );
    } else if (!value.isBuffering && _isBuffering) {
      _isBuffering = false;
      if (_bufferStartTime != null) {
        final bufferDuration =
            DateTime.now().difference(_bufferStartTime!).inMilliseconds / 1000;
        _analyticsService.trackBufferEnd(
          videoId: _videoId,
          duration: bufferDuration,
          quality: _currentQuality,
        );
      }
    }

    // Track video complete
    if (value.position >= value.duration &&
        value.duration.inSeconds > 0 &&
        !value.isPlaying) {
      _analyticsService.trackComplete(
        videoId: _videoId,
        duration: value.duration.inSeconds.toDouble(),
      );
    }

    // Call addListener callback if provided
    widget.addListener?.call(value.duration, value.position);

    // Update UI
    if (mounted) {
      setState(() {});
    }
  }

  /// Fetch quality sizes from backend API
  Future<void> _fetchQualitySizesFromApi() async {
    try {
      final videoId = _videoId;
      if (videoId == 'Unknown') {
        if (kDebugMode) {
          print('Cannot fetch quality sizes: videoId is unknown');
        }
        return;
      }

      // Build API URL for play endpoint (includes quality sizes)
      final uri = Uri.parse(widget.url);
      final baseUrl = '${uri.scheme}://${uri.host}';
      final apiUrl = '$baseUrl/api/v1/videos/$videoId/play';

      if (kDebugMode) {
        print('Fetching quality sizes from: $apiUrl');
      }

      // Use auth headers from widget if available, otherwise use analytics auth token
      final headers = Map<String, String>.from(widget.headers ?? {});

      // Try to add Authorization header if not present
      if (!headers.containsKey('Authorization') &&
          widget.analyticsConfig?.authToken != null) {
        headers['Authorization'] =
            'Bearer ${widget.analyticsConfig!.authToken}';
      }

      if (kDebugMode) {
        print('Fetching with headers: ${headers.keys.toList()}');
        print('Has Authorization: ${headers.containsKey('Authorization')}');
      }

      final response = await http.get(
        Uri.parse(apiUrl),
        headers: headers,
      );

      if (response.statusCode != 200) {
        if (kDebugMode) {
          print('Failed to fetch quality sizes: ${response.statusCode}');
          print('Response body: ${response.body}');
        }
        return;
      }

      final data = jsonDecode(response.body);
      if (data['success'] != true || data['data'] == null) {
        if (kDebugMode) {
          print('Invalid response from play API');
        }
        return;
      }

      final playData = data['data'] as Map<String, dynamic>;
      final qualitiesList = playData['qualities'] as List<dynamic>?;

      if (qualitiesList == null || qualitiesList.isEmpty) {
        if (kDebugMode) {
          print('No qualities found in API response');
        }
        return;
      }

      final qualities = <M3U8Data>[
        M3U8Data(dataQuality: 'Auto', dataURL: widget.url),
      ];

      for (final q in qualitiesList) {
        final qualityData = q as Map<String, dynamic>;
        final quality = qualityData['quality'] as String?;
        final url = qualityData['url'] as String?;
        final width = qualityData['width'] as int?;
        final height = qualityData['height'] as int?;
        final sizeBytes = qualityData['fileSize'] as int?;
        final bandwidth = qualityData['bandwidth'] as int?;

        if (quality != null && url != null) {
          qualities.add(M3U8Data(
            dataQuality: quality,
            dataURL: url,
            fileSize: sizeBytes,
            bandwidth: bandwidth,
            width: width,
            height: height,
          ));

          if (kDebugMode) {
            print(
                'Added quality: $quality (${width}x$height) - ${sizeBytes ?? 0} bytes');
          }
        }
      }

      if (mounted && qualities.length > 1) {
        setState(() {
          _qualities = qualities;
        });
        if (kDebugMode) {
          print('Loaded ${qualities.length - 1} qualities from API');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching quality sizes from API: $e');
      }
    }
  }

  Future<void> _fetchQualities(String url) async {
    try {
      final response = await http.get(
        Uri.parse(url),
        headers: widget.headers,
      );

      if (response.statusCode != 200) return;

      final content = utf8.decode(response.bodyBytes);
      final qualities = <M3U8Data>[
        M3U8Data(dataQuality: 'Auto', dataURL: url),
      ];

      if (kDebugMode) {
        print('Fetching qualities from manifest at $url');
      }

      // Parse HLS master playlist line by line
      final lines = content.split('\n');
      String? currentStreamInfo;

      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();

        if (line.startsWith('#EXT-X-STREAM-INF:')) {
          currentStreamInfo = line;
          continue;
        }

        // If we have stream info and this line is a URL
        if (currentStreamInfo != null &&
            line.isNotEmpty &&
            !line.startsWith('#')) {
          // Parse attributes from EXT-X-STREAM-INF
          debugPrint('Current stream info: $currentStreamInfo');
          final resolution = _extractAttribute(currentStreamInfo, 'RESOLUTION');
          final fileSize = _extractAttribute(currentStreamInfo, 'FILE-SIZE');
          final bandwidth = _extractAttribute(currentStreamInfo, 'BANDWIDTH');
          final frameRate = _extractAttribute(currentStreamInfo, 'FRAME-RATE');

          if (kDebugMode) {
            print('Parsed quality data:');
            print('  - URL: $line');
            print('  - Resolution: $resolution');
            print('  - FileSize: $fileSize');
            print('  - Bandwidth: $bandwidth');
            print('  - FrameRate: $frameRate');
          }

          // Build full URL
          String fullUrl;
          if (line.startsWith('http')) {
            fullUrl = line;
          } else {
            final baseUrl = url.substring(0, url.lastIndexOf('/') + 1);
            fullUrl = '$baseUrl$line';
          }

          // Parse resolution
          int? width, height;
          if (resolution != null && resolution.contains('x')) {
            final parts = resolution.split('x');
            width = int.tryParse(parts[0]);
            height = int.tryParse(parts[1]);
          }

          qualities.add(M3U8Data(
            dataQuality: resolution ?? 'Unknown',
            dataURL: fullUrl,
            fileSize: fileSize != null ? int.tryParse(fileSize) : null,
            bandwidth: bandwidth != null ? int.tryParse(bandwidth) : null,
            width: width,
            height: height,
            fps: frameRate != null ? int.tryParse(frameRate) : null,
          ));

          currentStreamInfo = null;
        }
      }

      if (mounted) {
        setState(() {
          _qualities = qualities;
        });
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching qualities: $e');
      }
    }
  }

  /// Extract attribute value from EXT-X-STREAM-INF line
  String? _extractAttribute(String line, String attribute) {
    // Handle quoted values like CODECS="..."
    final quotedRegex = RegExp('$attribute="([^"]*)"');
    final quotedMatch = quotedRegex.firstMatch(line);
    if (quotedMatch != null) {
      return quotedMatch.group(1);
    }

    // Handle unquoted values like BANDWIDTH=123456
    final unquotedRegex = RegExp('$attribute=([^,\\s]+)');
    final unquotedMatch = unquotedRegex.firstMatch(line);
    if (unquotedMatch != null) {
      return unquotedMatch.group(1);
    }

    return null;
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _seekForward() {
    if (_controller == null) return;
    final fromPosition = _controller!.value.position.inSeconds.toDouble();
    final newPosition =
        _controller!.value.position + const Duration(seconds: 10);
    final duration = _controller!.value.duration;
    final actualNewPosition = newPosition > duration ? duration : newPosition;

    _controller!.seekTo(actualNewPosition);

    // Track seek event
    _analyticsService.trackSeek(
      videoId: _videoId,
      fromPosition: fromPosition,
      toPosition: actualNewPosition.inSeconds.toDouble(),
    );
  }

  void _seekBackward() {
    if (_controller == null) return;
    final fromPosition = _controller!.value.position.inSeconds.toDouble();
    final newPosition =
        _controller!.value.position - const Duration(seconds: 10);
    final actualNewPosition =
        newPosition < Duration.zero ? Duration.zero : newPosition;

    _controller!.seekTo(actualNewPosition);

    // Track seek event
    _analyticsService.trackSeek(
      videoId: _videoId,
      fromPosition: fromPosition,
      toPosition: actualNewPosition.inSeconds.toDouble(),
    );
  }

  void _toggleFullScreen() {
    if (_controller == null) return;

    if (_isFullScreen) {
      // Exit fullscreen
      FullscreenManager.exitFullscreen(context);
      setState(() {
        _isFullScreen = false;
      });
      widget.onFullScreenChanged?.call(false);
    } else {
      // Enter fullscreen
      setState(() {
        _isFullScreen = true;
      });
      widget.onFullScreenChanged?.call(true);
      FullscreenManager.enterFullscreen(
        context,
        controller: _controller!,
        onExitFullscreen: () {
          setState(() {
            _isFullScreen = false;
          });
          widget.onFullScreenChanged?.call(false);
        },
        onSettingsTap: _showSettings,
      );
    }
  }

  void _showSettings() {
    if (_controller == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SettingsBottomSheet(
        qualities: _qualities.isNotEmpty
            ? _qualities
            : [M3U8Data(dataQuality: 'Auto', dataURL: widget.url)],
        currentQuality: _currentQuality,
        currentSpeed: _playbackSpeed,
        isLooping: _isLooping,
        videoId: _videoId,
        headers: widget.headers,
        onQualitySelected: _onQualitySelected,
        onSpeedSelected: _onSpeedSelected,
        onLoopToggled: _onLoopToggled,
      ),
    );
  }

  Future<void> _onQualitySelected(M3U8Data quality,
      {QualityChangeReason reason = QualityChangeReason.user}) async {
    if (quality.dataQuality == _currentQuality) return;
    if (_controller == null) return;

    final previousQuality = _currentQuality;

    // Save current position
    _lastPosition = _controller!.value.position;
    final wasPlaying = _controller!.value.isPlaying;

    setState(() {
      _currentQuality = quality.dataQuality ?? 'Auto';
      _isInitialized = false;
    });

    // Track quality change
    _analyticsService.trackQualityChange(
      videoId: _videoId,
      fromQuality: previousQuality,
      toQuality: _currentQuality,
      reason: reason,
    );

    // Check if this quality is downloaded (HLS)
    String? hlsPlaybackUrl;
    if (quality.dataQuality != 'Auto') {
      final isDownloaded = await HlsDownloadService.isDownloaded(
        _videoId,
        quality.dataQuality!,
      );
      if (isDownloaded) {
        hlsPlaybackUrl = await _hlsPlaybackManager.getPlaybackUrl(
          videoId: _videoId,
          quality: quality.dataQuality!,
        );
      }
    }

    // Check network - if offline and quality not downloaded, block switch
    final connectivity = Connectivity();
    final connectivityResult = await connectivity.checkConnectivity();
    final hasNetwork = !connectivityResult.contains(ConnectivityResult.none);

    if (!hasNetwork && hlsPlaybackUrl == null) {
      // Offline and quality not downloaded - cannot switch
      if (kDebugMode) {
        print(
            'Cannot switch to ${quality.dataQuality} - offline and not downloaded');
      }
      // Restore previous quality
      setState(() {
        _currentQuality = _currentQuality; // Keep current
        _isInitialized = true;
      });
      return;
    }

    // Dispose old controller
    _disposeController();

    // Initialize new controller
    try {
      if (hlsPlaybackUrl != null) {
        // iOS: Use networkUrl for local HTTP server (AVPlayer doesn't support local HLS files)
        // Android: Use file controller for temp files
        if (Platform.isIOS && hlsPlaybackUrl.startsWith('http://127.0.0.1')) {
          // iOS local HTTP server - use networkUrl
          _controller = VideoPlayerController.networkUrl(
            Uri.parse(hlsPlaybackUrl),
            formatHint: VideoFormat.hls,
            closedCaptionFile: widget.closedCaptionFile,
            videoPlayerOptions: widget.videoPlayerOptions,
          );
        } else {
          // Android: Play from local temp files
          _controller = VideoPlayerController.file(
            File(hlsPlaybackUrl),
            closedCaptionFile: widget.closedCaptionFile,
            videoPlayerOptions: widget.videoPlayerOptions,
          );
        }
      } else {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(quality.dataURL ?? widget.url),
          httpHeaders: widget.headers ?? const {},
          formatHint: VideoFormat.hls,
          closedCaptionFile: widget.closedCaptionFile,
          videoPlayerOptions: widget.videoPlayerOptions,
        );
      }

      await _controller!.initialize();
      _controller!.addListener(_videoListener);

      // Restore position
      if (_lastPosition != null) {
        await _controller!.seekTo(_lastPosition!);
        _lastPosition = null;
      }

      // Apply settings
      await _controller!.setLooping(_isLooping);
      await _controller!.setPlaybackSpeed(_playbackSpeed);

      if (wasPlaying) {
        await _controller!.play();
      }

      setState(() {
        _isInitialized = true;
      });

      widget.onVideoInitCompleted?.call(_controller!);
    } catch (e) {
      if (kDebugMode) {
        print('Error switching quality: $e');
      }
      setState(() {
        _hasError = true;
      });
    }
  }

  void _onSpeedSelected(double speed) {
    _playbackSpeed = speed;
    _controller?.setPlaybackSpeed(speed);
  }

  void _onLoopToggled(bool loop) {
    _isLooping = loop;
    _controller?.setLooping(loop);
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: widget.aspectRatio,
      child: Container(
        color: Colors.black,
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    if (_hasError) {
      return _buildErrorWidget();
    }

    if (!_isInitialized || _controller == null) {
      return VideoLoadingAnimation(
        primaryColor: widget.primaryColor,
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player
        Center(
          child: AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        ),
        // Buffering indicator
        if (_controller!.value.isBuffering)
          const Center(
            child: SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
            ),
          ),
        // Double tap seek handler
        DoubleTapSeek(
          onSeekForward: _seekForward,
          onSeekBackward: _seekBackward,
          onSingleTap: _toggleControls,
          child: Container(color: Colors.transparent),
        ),
        // Controls overlay
        VideoControls(
          controller: _controller!,
          isFullScreen: _isFullScreen,
          showControls: _showControls,
          onToggleControls: _toggleControls,
          onToggleFullScreen: _toggleFullScreen,
          onSettingsTap: _showSettings,
        ),
        // Mini progress bar when controls are hidden
        if (!_showControls)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<VideoPlayerValue>(
              valueListenable: _controller!,
              builder: (context, value, child) {
                final duration = value.duration.inMilliseconds.toDouble();
                final position = value.position.inMilliseconds.toDouble();
                return LinearProgressIndicator(
                  value: duration > 0 ? position / duration : 0,
                  backgroundColor: Colors.white.withAlpha((0.3 * 255).round()),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.primaryColor ?? Colors.red,
                  ),
                  minHeight: 2,
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: Colors.white.withValues(alpha: 0.7),
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Failed to load video',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 16),
          TextButton.icon(
            onPressed: () => _initializePlayer(isManualRetry: true),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            label: const Text(
              'Retry',
              style: TextStyle(color: Colors.white),
            ),
            style: TextButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
