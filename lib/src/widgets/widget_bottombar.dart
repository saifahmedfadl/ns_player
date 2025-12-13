import 'package:flutter/material.dart';
import 'package:ns_player/ns_player.dart';
import 'package:ns_player/src/utils/utils.dart';
import 'package:video_player/video_player.dart';

/// Widget use to display the bottom bar buttons and the time texts
class PlayerBottomBar extends StatelessWidget {
  /// Constructor
  const PlayerBottomBar({
    super.key,
    required this.controller,
    required this.showBottomBar,
    required this.fullScreen,
    this.onPlayButtonTap,
    this.videoDuration = "00:00:00",
    this.videoSeek = "00:00:00",
    this.videoStyle = const VideoStyle(),
    this.onFastForward,
    this.onRewind,
  });

  /// The controller of the playing video.
  final VideoPlayerController controller;

  final bool fullScreen;

  /// If set to [true] the bottom bar will appear and if you want that user can not interact with the bottom bar you can set it to [false].
  /// Default value is [true].
  final bool showBottomBar;

  /// The text to display the current position progress.
  final String videoSeek;

  /// The text to display the video's duration.
  final String videoDuration;

  /// The callback function execute when user tapped the play button.
  final void Function()? onPlayButtonTap;

  /// The model to provide custom style for the video display widget.
  final VideoStyle videoStyle;

  /// The callback function execute when user tapped the rewind button.
  final ValueChanged<VideoPlayerValue>? onRewind;

  /// The callback function execute when user tapped the forward button.
  final ValueChanged<VideoPlayerValue>? onFastForward;

  @override
  Widget build(BuildContext context) {
    return Visibility(
      visible: showBottomBar,
      child: Padding(
        padding: fullScreen
            ? const EdgeInsets.symmetric(horizontal: 20)
            : videoStyle.bottomBarPadding,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Stack(
            // mainAxisSize: MainAxisSize.min,
            // mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // fullScreen
              //     ? const SizedBox(height: 70,)
              //     : const SizedBox(height: 30,),
              Visibility(
                visible: !controller.value.isBuffering,
                child: Align(
                  alignment: Alignment.center,
                  child: Padding(
                    padding: videoStyle.videoDurationsPadding ??
                        const EdgeInsets.only(top: 8.0),
                    child: SizedBox(
                      width: fullScreen
                          ? MediaQuery.of(context).size.width / 3
                          : MediaQuery.of(context).size.width / 2,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        mainAxisSize: MainAxisSize.max,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          InkWell(
                            onTap: () {
                              controller.rewind().then((value) {
                                onRewind?.call(controller.value);
                              });
                            },
                            child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: videoStyle.backwardIcon ??
                                    Icon(
                                      Icons.replay_10_rounded,
                                      color: videoStyle.forwardIconColor,
                                      size: fullScreen ? 25 : 20,
                                      // size: videoStyle.forwardAndBackwardBtSize,
                                    )),
                          ),
                          InkWell(
                            onTap: onPlayButtonTap,
                            child: () {
                              var defaultIcon = Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.5),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  controller.value.isPlaying
                                      ? Icons.pause_outlined
                                      : Icons.play_arrow_outlined,
                                  color: videoStyle.playButtonIconColor ??
                                      Colors.white,
                                  size: fullScreen ? 35 : 30,
                                  // videoStyle.playButtonIconSize ?? (fullScreen ? 35: 25),
                                ),
                              );
                              if (videoStyle.playIcon != null &&
                                  videoStyle.pauseIcon == null) {
                                return controller.value.isPlaying
                                    ? defaultIcon
                                    : videoStyle.playIcon;
                              } else if (videoStyle.pauseIcon != null &&
                                  videoStyle.playIcon == null) {
                                return controller.value.isPlaying
                                    ? videoStyle.pauseIcon
                                    : defaultIcon;
                              } else if (videoStyle.playIcon != null &&
                                  videoStyle.pauseIcon != null) {
                                return controller.value.isPlaying
                                    ? videoStyle.pauseIcon
                                    : videoStyle.playIcon;
                              }
                              return defaultIcon;
                            }(),
                          ),
                          InkWell(
                            onTap: () {
                              controller.fastForward().then((value) {
                                onFastForward?.call(controller.value);
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.5),
                                shape: BoxShape.circle,
                              ),
                              child: videoStyle.forwardIcon ??
                                  Icon(
                                    Icons.forward_10_rounded,
                                    color: videoStyle.forwardIconColor,
                                    size: fullScreen ? 25 : 20,
                                    // size: videoStyle.forwardAndBackwardBtSize,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: Text(
                            videoSeek,
                            style: videoStyle.videoSeekStyle ??
                                const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                          ),
                        ),
                        Text(
                          " / ",
                          style: videoStyle.videoSeekStyle ??
                              const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                        ),
                        Text(
                          videoDuration,
                          style: videoStyle.videoDurationStyle ??
                              const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white70,
                              ),
                        ),
                        const Spacer(),
                      ],
                    ),
                    SizedBox(
                      height: 15,
                      child: VideoProgressIndicator(
                        controller,
                        allowScrubbing: videoStyle.allowScrubbing ?? true,
                        colors: videoStyle.progressIndicatorColors ??
                            const VideoProgressColors(
                              playedColor: Color.fromARGB(255, 206, 3, 3),
                              bufferedColor: Color.fromARGB(169, 77, 68, 68),
                              backgroundColor:
                                  Color.fromARGB(27, 255, 255, 255),
                            ),
                        padding: videoStyle.progressIndicatorPadding ??
                            const EdgeInsets.only(top: 10.0),
                      ),
                    ),
                    fullScreen
                        ? const SizedBox(
                            height: 30,
                          )
                        : const SizedBox(
                            height: 0,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Duration durationRangeToDuration(List<DurationRange> durationRange) {
    if (durationRange.isEmpty) {
      return Duration.zero;
    }
    return durationRange.first.end;
  }
}
