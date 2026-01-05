import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/download/download_notification_service.dart';
import '../../core/download/hls_download_service.dart';
import '../../model/m3u8.dart';

/// Settings bottom sheet with quality selection and download management
class SettingsBottomSheet extends StatefulWidget {
  final List<M3U8Data> qualities;
  final String currentQuality;
  final double currentSpeed;
  final bool isLooping;
  final String videoId;
  final Map<String, String>? headers;
  final void Function(M3U8Data quality) onQualitySelected;
  final void Function(double speed) onSpeedSelected;
  final void Function(bool loop) onLoopToggled;

  const SettingsBottomSheet({
    super.key,
    required this.qualities,
    required this.currentQuality,
    required this.currentSpeed,
    required this.isLooping,
    required this.videoId,
    this.headers,
    required this.onQualitySelected,
    required this.onSpeedSelected,
    required this.onLoopToggled,
  });

  @override
  State<SettingsBottomSheet> createState() => _SettingsBottomSheetState();
}

class _SettingsBottomSheetState extends State<SettingsBottomSheet> {
  final List<double> _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF212121),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((0.3 * 255).round()),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Settings options
          _buildSettingsTile(
            icon: Icons.high_quality_rounded,
            title: 'Quality',
            value: _formatQuality(widget.currentQuality),
            onTap: () => _showQualityPicker(context),
          ),
          _buildSettingsTile(
            icon: Icons.speed_rounded,
            title: 'Playback speed',
            value: widget.currentSpeed == 1.0
                ? 'Normal'
                : '${widget.currentSpeed}x',
            onTap: () => _showSpeedPicker(context),
          ),
          _buildSettingsTile(
            icon: widget.isLooping
                ? Icons.repeat_one_rounded
                : Icons.repeat_rounded,
            title: 'Loop',
            value: widget.isLooping ? 'On' : 'Off',
            onTap: () {
              widget.onLoopToggled(!widget.isLooping);
              Navigator.pop(context);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String value,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 24),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: Colors.white.withAlpha((0.7 * 255).round()),
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.white.withAlpha((0.5 * 255).round()),
            size: 20,
          ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatQuality(String quality) {
    if (quality == 'Auto') return 'Auto';
    final parts = quality.split('x');
    if (parts.length == 2) {
      return '${parts[1]}p';
    }
    return quality;
  }

  void _showQualityPicker(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _QualityPickerSheet(
        qualities: widget.qualities,
        currentQuality: widget.currentQuality,
        videoId: widget.videoId,
        headers: widget.headers,
        onQualitySelected: widget.onQualitySelected,
      ),
    );
  }

  void _showSpeedPicker(BuildContext context) {
    Navigator.pop(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF212121),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withAlpha((0.3 * 255).round()),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Playback speed',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
                child: SingleChildScrollView(
              child: Column(
                children: [
                  ...List.generate(_speeds.length, (index) {
                    final speed = _speeds[index];
                    final isSelected = speed == widget.currentSpeed;
                    return ListTile(
                      leading: Icon(
                        Icons.check_rounded,
                        color: isSelected ? Colors.red : Colors.transparent,
                        size: 20,
                      ),
                      title: Text(
                        speed == 1.0 ? 'Normal' : '${speed}x',
                        style: TextStyle(
                          color: isSelected ? Colors.red : Colors.white,
                          fontSize: 15,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                      onTap: () {
                        widget.onSpeedSelected(speed);
                        Navigator.pop(context);
                      },
                    );
                  }),
                ],
              ),
            )),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

/// Quality picker with download options
class _QualityPickerSheet extends StatefulWidget {
  final List<M3U8Data> qualities;
  final String currentQuality;
  final String videoId;
  final Map<String, String>? headers;
  final void Function(M3U8Data quality) onQualitySelected;

  const _QualityPickerSheet({
    required this.qualities,
    required this.currentQuality,
    required this.videoId,
    this.headers,
    required this.onQualitySelected,
  });

  @override
  State<_QualityPickerSheet> createState() => _QualityPickerSheetState();
}

class _QualityPickerSheetState extends State<_QualityPickerSheet> {
  final Map<String, bool> _downloadedStatus = {};
  final Map<String, HlsDownloadProgress?> _downloadProgress = {};
  StreamSubscription<HlsDownloadProgress>? _progressSubscription;

  @override
  void initState() {
    super.initState();
    _checkDownloadStatus();
    _subscribeToDownloadProgress();
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    super.dispose();
  }

  void _subscribeToDownloadProgress() {
    _progressSubscription =
        HlsDownloadService.progressStream.listen((progress) {
      if (progress.videoId == widget.videoId && mounted) {
        setState(() {
          _downloadProgress[progress.quality] = progress;
          if (progress.status == HlsDownloadStatus.completed) {
            _downloadedStatus[progress.quality] = true;
            _downloadProgress.remove(progress.quality);
          }
          // Keep failed status in progress map to show error UI
          if (progress.status == HlsDownloadStatus.failed) {
            _downloadProgress[progress.quality] = progress;
          }
        });
      }
    });
  }

  Future<void> _checkDownloadStatus() async {
    for (final quality in widget.qualities) {
      if (quality.dataQuality != null && quality.dataQuality != 'Auto') {
        // Check download using only videoId + quality (no URL matching)
        final isDownloaded = await HlsDownloadService.isDownloaded(
          widget.videoId,
          quality.dataQuality!,
        );
        if (mounted) {
          setState(() {
            _downloadedStatus[quality.dataQuality!] = isDownloaded;
          });
        }
      }
    }

    // Check for active downloads
    final activeDownloads = HlsDownloadService.getActiveDownloads();
    for (final task in activeDownloads) {
      if (task.videoId == widget.videoId && mounted) {
        setState(() {
          _downloadProgress[task.quality.dataQuality ?? ''] =
              HlsDownloadProgress(
            videoId: task.videoId,
            quality: task.quality.dataQuality ?? '',
            downloadedSegments: task.downloadedSegments,
            totalSegments: task.totalSegments,
            downloadedBytes: task.downloadedBytes,
            totalBytes: task.totalBytes,
            speed: task.speed,
            status: task.status,
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF212121),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha((0.3 * 255).round()),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Video quality',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: widget.qualities
                    .map((quality) => _buildQualityTile(quality))
                    .toList(),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildQualityTile(M3U8Data quality) {
    final qualityName = quality.dataQuality ?? 'Unknown';
    final isSelected = qualityName == widget.currentQuality;
    final isAuto = qualityName == 'Auto';
    final isDownloaded = _downloadedStatus[qualityName] ?? false;
    final progress = _downloadProgress[qualityName];
    final isDownloading = progress?.status == HlsDownloadStatus.downloading;

    return ListTile(
      leading: Icon(
        Icons.check_rounded,
        color: isSelected ? Colors.red : Colors.transparent,
        size: 20,
      ),
      title: Row(
        children: [
          Text(
            _formatQuality(qualityName),
            style: TextStyle(
              color: isSelected ? Colors.red : Colors.white,
              fontSize: 15,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (isDownloaded) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withAlpha((0.2 * 255).round()),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Downloaded',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      trailing: isAuto
          ? null
          : _buildDownloadButton(
              quality, isDownloaded, isDownloading, progress),
      onTap: () {
        widget.onQualitySelected(quality);
        Navigator.pop(context);
      },
    );
  }

  Widget _buildDownloadButton(
    M3U8Data quality,
    bool isDownloaded,
    bool isDownloading,
    HlsDownloadProgress? progress,
  ) {
    // Check for failed download - show error UI with retry
    final isFailed = progress?.status == HlsDownloadStatus.failed;
    if (isFailed && progress != null) {
      return _buildFailedDownloadUI(quality, progress);
    }

    // Check for active download states (downloading OR paused)
    final isPaused = progress?.status == HlsDownloadStatus.paused;

    if ((isDownloading || isPaused) && progress != null) {
      return _buildDownloadProgress(quality, progress);
    }

    if (isDownloaded) {
      return _buildDeleteButton(quality);
    }

    // Check if there's a paused download that can be resumed
    return FutureBuilder<bool>(
      future: HlsDownloadService.isPaused(
          widget.videoId, quality.dataQuality ?? ''),
      builder: (context, snapshot) {
        if (snapshot.data == true) {
          // Show resume UI for paused downloads
          return _buildPausedResumeButton(quality);
        }
        return IconButton(
          icon: const Icon(
            Icons.download_rounded,
            color: Colors.white,
            size: 22,
          ),
          onPressed: () => _startDownload(quality),
        );
      },
    );
  }

  /// Build UI for failed download with error message and retry button
  Widget _buildFailedDownloadUI(
      M3U8Data quality, HlsDownloadProgress progress) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Error indicator with tooltip
        Tooltip(
          message: progress.errorMessage ?? 'Download failed',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.red.withAlpha((0.2 * 255).round()),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 14),
                const SizedBox(width: 4),
                const Text(
                  'Failed',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        // Retry button
        IconButton(
          icon: const Icon(
            Icons.refresh_rounded,
            color: Colors.orange,
            size: 20,
          ),
          onPressed: () {
            // Clear the failed state and retry
            setState(() {
              _downloadProgress.remove(quality.dataQuality);
            });
            _startDownload(quality);
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          tooltip: 'Retry download',
        ),
        // Dismiss button
        IconButton(
          icon: const Icon(
            Icons.close_rounded,
            color: Colors.grey,
            size: 18,
          ),
          onPressed: () {
            setState(() {
              _downloadProgress.remove(quality.dataQuality);
            });
          },
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          tooltip: 'Dismiss',
        ),
      ],
    );
  }

  Widget _buildPausedResumeButton(M3U8Data quality) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange.withAlpha((0.2 * 255).round()),
            borderRadius: BorderRadius.circular(4),
          ),
          child: const Text(
            'Paused',
            style: TextStyle(
              color: Colors.orange,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.play_arrow_rounded,
            color: Colors.green,
            size: 22,
          ),
          onPressed: () => _resumeDownload(quality),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
        IconButton(
          icon: const Icon(
            Icons.delete_outline_rounded,
            color: Colors.red,
            size: 20,
          ),
          onPressed: () => _cancelDownload(quality),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        ),
      ],
    );
  }

  Widget _buildDownloadProgress(
      M3U8Data quality, HlsDownloadProgress progress) {
    final isPaused = progress.status == HlsDownloadStatus.paused;

    return SizedBox(
      width: 150,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${progress.percentage.toStringAsFixed(0)}%${isPaused ? ' (Paused)' : ''}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                if (!isPaused)
                  Text(
                    progress.speedFormatted,
                    style: TextStyle(
                      color: Colors.white.withAlpha((0.6 * 255).round()),
                      fontSize: 10,
                    ),
                  ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress.percentage / 100,
                    backgroundColor:
                        Colors.white.withAlpha((0.2 * 255).round()),
                    valueColor: AlwaysStoppedAnimation<Color>(
                        isPaused ? Colors.grey : Colors.red),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () =>
                isPaused ? _resumeDownload(quality) : _pauseDownload(quality),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: Colors.red,
              size: 20,
            ),
            onPressed: () => _cancelDownload(quality),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildDeleteButton(M3U8Data quality) {
    return IconButton(
      icon: const Icon(
        Icons.delete_outline_rounded,
        color: Colors.red,
        size: 22,
      ),
      onPressed: () {
        _showDeleteConfirmation(quality);
      },
    );
  }

  String _formatQuality(String quality) {
    if (quality == 'Auto') return 'Auto (Recommended)';
    final parts = quality.split('x');
    if (parts.length == 2) {
      return '${parts[1]}p';
    }
    return quality;
  }

  Future<void> _startDownload(M3U8Data quality) async {
    if (quality.dataURL == null || quality.dataQuality == null) return;

    // Show confirmation dialog first
    final confirmed = await _showDownloadConfirmation(quality);
    if (confirmed != true) return;

    // Initialize notification service for download progress
    await DownloadNotificationService.instance.initialize();

    // Start download and update UI immediately
    setState(() {
      _downloadProgress[quality.dataQuality!] = HlsDownloadProgress(
        videoId: widget.videoId,
        quality: quality.dataQuality!,
        downloadedSegments: 0,
        totalSegments: 0,
        downloadedBytes: 0,
        totalBytes: quality.fileSize ?? 0,
        speed: 0,
        status: HlsDownloadStatus.downloading,
      );
    });

    await HlsDownloadService.startDownload(
      videoId: widget.videoId,
      quality: quality,
      headers: widget.headers,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress[quality.dataQuality!] = progress;
            if (progress.status == HlsDownloadStatus.completed) {
              _downloadedStatus[quality.dataQuality!] = true;
            }
          });
        }
      },
      onComplete: (path) {
        if (mounted) {
          setState(() {
            _downloadedStatus[quality.dataQuality!] = true;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _downloadProgress.remove(quality.dataQuality);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Download failed: $error')),
          );
        }
      },
    );
  }

  Future<void> _pauseDownload(M3U8Data quality) async {
    if (quality.dataQuality == null) return;
    await HlsDownloadService.pauseDownload(
        widget.videoId, quality.dataQuality!);
    setState(() {
      final current = _downloadProgress[quality.dataQuality!];
      if (current != null) {
        _downloadProgress[quality.dataQuality!] = HlsDownloadProgress(
          videoId: current.videoId,
          quality: current.quality,
          downloadedSegments: current.downloadedSegments,
          totalSegments: current.totalSegments,
          downloadedBytes: current.downloadedBytes,
          totalBytes: current.totalBytes,
          speed: 0,
          status: HlsDownloadStatus.paused,
        );
      }
    });
  }

  Future<void> _resumeDownload(M3U8Data quality) async {
    if (quality.dataQuality == null) return;

    await DownloadNotificationService.instance.initialize();

    await HlsDownloadService.resumeDownload(
      videoId: widget.videoId,
      quality: quality.dataQuality!,
      qualityData: quality,
      headers: widget.headers,
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _downloadProgress[quality.dataQuality!] = progress;
            if (progress.status == HlsDownloadStatus.completed) {
              _downloadedStatus[quality.dataQuality!] = true;
            }
          });
        }
      },
      onComplete: (path) {
        if (mounted) {
          setState(() {
            _downloadedStatus[quality.dataQuality!] = true;
          });
        }
      },
      onError: (error) {
        if (mounted) {
          setState(() {
            _downloadProgress.remove(quality.dataQuality);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Resume failed: $error')),
          );
        }
      },
    );
  }

  Future<bool?> _showDownloadConfirmation(M3U8Data quality) async {
    print('Quality: ${quality.toJson()}');
    // Use file size from API (backend-driven)
    final fileSize = quality.fileSize ?? 0;

    // Check available storage
    final availableStorage = await _getAvailableStorage();
    final hasEnoughSpace = availableStorage > fileSize;

    if (!mounted) return false;

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF303030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.download_rounded, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              'Download ${_formatQuality(quality.dataQuality ?? '')}?',
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // _buildInfoRow(
            //   'File size',
            //   quality.fileSizeFormatted,
            //   Icons.storage_rounded,
            // ),
            // // Only show available storage on Android (iOS storage APIs are unreliable)
            // if (!Platform.isIOS) ...[
            //   const SizedBox(height: 8),
            //   _buildInfoRow(
            //     'Available space',
            //     _formatBytes(availableStorage),
            //     Icons.sd_storage_rounded,
            //     color: hasEnoughSpace ? Colors.green : Colors.red,
            //   ),
            // ],
            // if (!hasEnoughSpace && !Platform.isIOS) ...[
            //   const SizedBox(height: 12),
            //   Container(
            //     padding: const EdgeInsets.all(8),
            //     decoration: BoxDecoration(
            //       color: Colors.red.withValues(alpha: 0.2),
            //       borderRadius: BorderRadius.circular(8),
            //     ),
            //     child: const Row(
            //       children: [
            //         Icon(Icons.warning_rounded, color: Colors.red, size: 20),
            //         SizedBox(width: 8),
            //         Expanded(
            //           child: Text(
            //             'Not enough storage space!',
            //             style: TextStyle(color: Colors.red, fontSize: 13),
            //           ),
            //         ),
            //       ],
            //     ),
            //   ),
            // ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            // On iOS, always allow download (storage check unreliable)
            // On Android, check if there's enough space
            onPressed: (Platform.isIOS || hasEnoughSpace)
                ? () => Navigator.pop(context, true)
                : null,
            child: Text(
              'Download',
              style: TextStyle(
                color: (Platform.isIOS || hasEnoughSpace)
                    ? Colors.red
                    : Colors.grey,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon,
      {Color? color}) {
    return Row(
      children: [
        Icon(icon, color: color ?? Colors.white70, size: 18),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
        ),
        Text(
          value,
          style: TextStyle(
            color: color ?? Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Future<int> _getAvailableStorage() async {
    try {
      final directory = await getApplicationDocumentsDirectory();

      if (Platform.isAndroid) {
        // On Android, use statfs to get available space
        final stat = await Process.run('df', [directory.path]);
        if (stat.exitCode == 0) {
          final lines = (stat.stdout as String).split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              // Available space is typically in the 4th column (in 1K blocks)
              final availableKB = int.tryParse(parts[3]) ?? 0;
              return availableKB * 1024;
            }
          }
        }
      } else if (Platform.isIOS) {
        // On iOS, use FileManager to get available space
        // This uses NSFileManager's systemFreeSize attribute
        final stat = await Process.run('df', ['-k', directory.path]);
        if (stat.exitCode == 0) {
          final lines = (stat.stdout as String).split('\n');
          if (lines.length > 1) {
            final parts = lines[1].split(RegExp(r'\s+'));
            if (parts.length >= 4) {
              // Available space in 1K blocks (column 3 on iOS)
              final availableKB = int.tryParse(parts[3]) ?? 0;
              return availableKB * 1024;
            }
          }
        }

        // iOS-specific fallback: Use statfs system call via df with better parsing
        try {
          final result = await Process.run('df', [directory.path]);
          if (result.exitCode == 0) {
            final output = result.stdout.toString();
            // Parse: Filesystem  512-blocks  Used  Available  Capacity  iused  ifree  %iused  Mounted
            final lines = output.split('\n');
            if (lines.length > 1) {
              final parts = lines[1].trim().split(RegExp(r'\s+'));
              // On iOS, Available is typically column 3 (0-indexed)
              if (parts.length >= 4) {
                final available512Blocks = int.tryParse(parts[3]) ?? 0;
                return available512Blocks *
                    512; // Convert 512-byte blocks to bytes
              }
            }
          }
        } catch (_) {}
      }

      // Final fallback - return 10GB as conservative estimate
      return 10 * 1024 * 1024 * 1024;
    } catch (e) {
      // Conservative fallback
      return 10 * 1024 * 1024 * 1024;
    }
  }

  String _formatBytes(int bytes) {
    if (bytes <= 0) return 'Unknown';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<void> _cancelDownload(M3U8Data quality) async {
    if (quality.dataQuality == null) return;

    await HlsDownloadService.cancelDownload(
        widget.videoId, quality.dataQuality!);
    setState(() {
      _downloadProgress.remove(quality.dataQuality);
    });
  }

  void _showDeleteConfirmation(M3U8Data quality) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF303030),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Delete download?',
          style: TextStyle(color: Colors.white, fontSize: 18),
        ),
        content: Text(
          'This will remove the downloaded ${_formatQuality(quality.dataQuality ?? '')} video from your device.',
          style: TextStyle(
              color: Colors.white.withAlpha((0.7 * 255).round()), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.white)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              if (quality.dataQuality != null) {
                await HlsDownloadService.deleteDownload(
                  widget.videoId,
                  quality.dataQuality!,
                );
                setState(() {
                  _downloadedStatus[quality.dataQuality!] = false;
                });
              }
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
