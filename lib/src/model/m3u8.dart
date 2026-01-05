/// Video quality data - can be populated from API or parsed from HLS manifest
class M3U8Data {
  /// Quality label (e.g., "720p", "1080p", "Auto")
  final String? dataQuality;

  /// Playlist URL for this quality
  final String? dataURL;

  /// Exact file size in bytes (from API/storage)
  final int? fileSize;

  /// Bandwidth in bits per second
  final int? bandwidth;

  /// Video width in pixels
  final int? width;

  /// Video height in pixels
  final int? height;

  /// Video codec (e.g., "h264", "hevc")
  final String? codec;

  /// Audio codec (e.g., "aac", "opus")
  final String? audioCodec;

  /// Frames per second
  final int? fps;

  /// Number of HLS segments (for download progress)
  final int? segmentCount;

  /// Total duration in seconds
  final double? duration;

  /// Constructor
  M3U8Data({
    this.dataURL,
    this.dataQuality,
    this.fileSize,
    this.bandwidth,
    this.width,
    this.height,
    this.codec,
    this.audioCodec,
    this.fps,
    this.segmentCount,
    this.duration,
  });

  /// Create from API response (backend-driven)
  factory M3U8Data.fromJson(Map<String, dynamic> json) {
    return M3U8Data(
      dataQuality: json['quality'] as String?,
      dataURL: json['url'] as String?,
      fileSize: json['fileSize'] as int?,
      bandwidth: json['bandwidth'] as int?,
      width: json['width'] as int?,
      height: json['height'] as int?,
      codec: json['codec'] as String?,
      audioCodec: json['audioCodec'] as String?,
      fps: json['fps'] as int?,
      segmentCount: json['segmentCount'] as int?,
      duration: (json['duration'] as num?)?.toDouble(),
    );
  }

  /// Convert to JSON (for local storage/caching)
  Map<String, dynamic> toJson() {
    return {
      'quality': dataQuality,
      'url': dataURL,
      'fileSize': fileSize,
      'bandwidth': bandwidth,
      'width': width,
      'height': height,
      'codec': codec,
      'audioCodec': audioCodec,
      'fps': fps,
      'segmentCount': segmentCount,
      'duration': duration,
    };
  }

  /// Get display label (e.g., "720p HD")
  String get displayLabel {
    if (dataQuality == 'Auto') return 'Auto';
    if (height != null) {
      final label = '${height}p';
      if (height! >= 1080) return '$label HD';
      if (height! >= 720) return '$label HD';
      return label;
    }
    // Fallback: parse from quality string like "1280x720"
    if (dataQuality != null && dataQuality!.contains('x')) {
      final parts = dataQuality!.split('x');
      if (parts.length == 2) {
        return '${parts[1]}p';
      }
    }
    return dataQuality ?? 'Unknown';
  }

  /// Get formatted file size (e.g., "150 MB")
  String get fileSizeFormatted {
    if (fileSize == null || fileSize == 0) return 'Unknown size';
    if (fileSize! < 1024) return '$fileSize B';
    if (fileSize! < 1024 * 1024) {
      return '${(fileSize! / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize! < 1024 * 1024 * 1024) {
      return '${(fileSize! / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize! / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Copy with new values
  M3U8Data copyWith({
    String? dataQuality,
    String? dataURL,
    int? fileSize,
    int? bandwidth,
    int? width,
    int? height,
    String? codec,
    String? audioCodec,
    int? fps,
    int? segmentCount,
    double? duration,
  }) {
    return M3U8Data(
      dataQuality: dataQuality ?? this.dataQuality,
      dataURL: dataURL ?? this.dataURL,
      fileSize: fileSize ?? this.fileSize,
      bandwidth: bandwidth ?? this.bandwidth,
      width: width ?? this.width,
      height: height ?? this.height,
      codec: codec ?? this.codec,
      audioCodec: audioCodec ?? this.audioCodec,
      fps: fps ?? this.fps,
      segmentCount: segmentCount ?? this.segmentCount,
      duration: duration ?? this.duration,
    );
  }
}
