import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:ns_player/ns_player.dart';
import 'package:ns_player/src/model/models.dart';
import 'package:ns_player/src/utils/utils.dart';
import 'package:ns_player/src/widgets/video_loading.dart';
import 'package:ns_player/src/widgets/video_quality_picker.dart';
import 'package:ns_player/src/widgets/widget_bottombar.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'responses/regex_response.dart';

class NsPlayer extends StatefulWidget {
  /// **Video source**
  /// ```dart
  /// url:"https://example.com/index.m3u8";
  /// ```
  final String url;

  /// Custom style for the video player
  ///```dart
  ///videoStyle : VideoStyle(
  ///     playIcon =  Icon(Icons.play_arrow),
  ///     pauseIcon = Icon(Icons.pause),
  ///     fullscreenIcon =  Icon(Icons.fullScreen),
  ///     forwardIcon =  Icon(Icons.skip_next),
  ///     backwardIcon =  Icon(Icons.skip_previous),
  ///     progressIndicatorColors = VideoProgressColors(
  ///       playedColor: Colors.green,
  ///     ),
  ///     qualityStyle = const TextStyle(
  ///       color: Colors.white,
  ///     ),
  ///      qaShowStyle = const TextStyle(
  ///       color: Colors.white,
  ///     ),
  ///   );
  ///```
  final VideoStyle videoStyle;

  final VideoLoadingStyle videoLoadingStyle;

  /// Video aspect ratio. Ex: [aspectRatio: 16 / 9 ]
  final double aspectRatio;

  /// Callback function for on fullscreen event.
  final void Function(bool fullScreenTurnedOn)? onFullScreen;

  /// Callback function for start playing a video event. The function will return the type of the playing video.
  final void Function(String videoType)? onPlayingVideo;

  /// Callback function for tapping play video button event.
  final void Function(bool isPlaying)? onPlayButtonTap;

  /// Callback function for fast forward button tap event.
  final ValueChanged<VideoPlayerValue>? onFastForward;

  /// Callback function for rewind button tap event.
  final ValueChanged<VideoPlayerValue>? onRewind;

  /// Callback function for live direct button tap event.
  final ValueChanged<VideoPlayerValue>? onLiveDirectTap;

  /// Callback function for showing menu event.
  final void Function(bool showMenu, bool m3u8Show)? onShowMenu;

  /// Callback function for video init completed event.
  /// This function will expose the video controller and you can use it to track the video progress.
  final void Function(VideoPlayerController controller)? onVideoInitCompleted;

  /// The headers for the video url request.
  final Map<String, String>? headers;

  /// If set to [true] the video will be played after the video initialize steps are completed and vice versa.
  /// Default value is [true].
  final bool autoPlayVideoAfterInit;

  /// If set to [true] the video will be played in full screen mode after the video initialize steps is completed and vice versa.
  /// Default value is [false].
  final bool displayFullScreenAfterInit;

  /// Callback function execute when the file cached to the device local storage and it will return a list of
  /// paths of the cached files.
  ///
  /// ***This function will be called only when the [allowCacheFile] property is set to true.***
  final void Function(List<File>? files)? onCacheFileCompleted;

  /// Callback function execute when there is an error occurs while caching the file.
  /// The error will be return within the function.
  final void Function(dynamic error)? onCacheFileFailed;

  /// If set to [true] the video will be cached into the device local storage and the [onCacheFileCompleted]
  /// method will be executed after the file is cached.
  final bool allowCacheFile;

  /// Callback method for closed caption file event.
  /// You have to return a [ClosedCaptionFile] object for this method.
  final Future<ClosedCaptionFile>? closedCaptionFile;

  /// Provide additional configuration options (optional).
  /// Like setting the audio mode to mix.
  final VideoPlayerOptions? videoPlayerOptions;

  ///
  /// ```dart
  /// NsPlayer(
  /// // url types = (m3u8[hls],.mp4,.mkv)
  ///   url : "video_url",
  /// // Video's style
  ///   videoStyle : VideoStyle(),
  /// // Video's loading style
  ///   videoLoadingStyle : VideoLoadingStyle(),
  /// // Video's aspect ratio
  ///   aspectRatio : 16/9,
  /// )
  /// ```
  const NsPlayer({
    super.key,
    required this.url,
    this.aspectRatio = 16 / 9,
    this.videoStyle = const VideoStyle(),
    this.videoLoadingStyle = const VideoLoadingStyle(),
    this.onFullScreen,
    this.onPlayingVideo,
    this.onPlayButtonTap,
    this.onShowMenu,
    this.onFastForward,
    this.onRewind,
    this.headers,
    this.autoPlayVideoAfterInit = true,
    this.displayFullScreenAfterInit = false,
    this.allowCacheFile = false,
    this.onCacheFileCompleted,
    this.onCacheFileFailed,
    this.onVideoInitCompleted,
    this.closedCaptionFile,
    this.videoPlayerOptions,
    this.onLiveDirectTap,
  });

  @override
  State<NsPlayer> createState() => _NsPlayerState();
}

class _NsPlayerState extends State<NsPlayer>
    with SingleTickerProviderStateMixin {
  /// Video play type (hls,mp4,mkv,offline)
  String? playType;

  ///for loap video
  bool loop = false;

  /// Animation Controller
  late AnimationController controlBarAnimationController;

  /// Video Top Bar Animation
  Animation<double>? controlTopBarAnimation;

  /// Video Bottom Bar Animation
  Animation<double>? controlBottomBarAnimation;

  /// Video Player Controller
  late VideoPlayerController controller;

  /// Video init error default :false
  bool hasInitError = false;

  /// Video Total Time duration
  String? videoDuration;

  /// Video Seed to
  String? videoSeek;

  /// Video duration 1
  Duration? duration;

  /// Video seek second by user
  double? videoSeekSecond;

  /// Video duration second
  double? videoDurationSecond;

  /// m3u8 data video list for user choice
  List<M3U8Data> m3u8UrlList = [];

  List<double> playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  double playbackSpeed = 1.0;

  /// m3u8 audio list
  List<AudioModel> audioList = [];

  /// m3u8 temp data
  String? m3u8Content;

  /// Subtitle temp data
  String? subtitleContent;

  /// Menu show m3u8 list
  bool m3u8Show = false;

  /// Video full screen
  bool fullScreen = false;

  /// Menu show
  bool showMenu = false;

  /// Auto show subtitle
  bool showSubtitles = false;

  /// Video status
  bool? isOffline;

  /// Video auto quality
  String m3u8Quality = "Auto";

  /// Time for duration
  Timer? showTime;

  /// Video quality overlay
  OverlayEntry? overlayEntry;

  /// Global key to calculate quality options
  GlobalKey videoQualityKey = GlobalKey();

  /// Last playing position of the current video before changing the quality
  Duration? lastPlayedPos;

  /// If set to true the live direct button will display with the live color
  /// and if not it will display with the disable color.
  bool isAtLivePosition = true;

  bool hideQualityList = false;

  @override
  void initState() {
    super.initState();

    urlCheck(widget.url);

    /// Control bar animation
    controlBarAnimationController = AnimationController(
        duration: const Duration(milliseconds: 300), vsync: this);
    controlTopBarAnimation = Tween(begin: -(36.0 + 0.0 * 2), end: 0.0)
        .animate(controlBarAnimationController);
    controlBottomBarAnimation = Tween(begin: -(36.0 + 0.0 * 2), end: 0.0)
        .animate(controlBarAnimationController);

    WidgetsBinding.instance.addPostFrameCallback((callback) {
      WidgetsBinding.instance.addPersistentFrameCallback((callback) {
        if (!mounted) return;
        var orientation = MediaQuery.of(context).orientation;
        bool? fullScr;

        if (orientation == Orientation.landscape) {
          // Horizontal screen
          fullScr = true;
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: [SystemUiOverlay.bottom],
          );
        } else if (orientation == Orientation.portrait) {
          // Portrait screen
          fullScr = false;
          SystemChrome.setEnabledSystemUIMode(
            SystemUiMode.manual,
            overlays: SystemUiOverlay.values,
          );
        }

        if (fullScr != fullScreen) {
          setState(() {
            fullScreen = !fullScreen;
            _navigateLocally(context);
            widget.onFullScreen?.call(fullScreen);
          });
        }
        // log('Controller Value=================>  ${controller.value.isBuffering.toString()}');
        WidgetsBinding.instance.scheduleFrame();
      });
    });

    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);

    if (widget.videoStyle.enableSystemOrientationsOverride) {
      SystemChrome.setPreferredOrientations(
        widget.videoStyle.orientation ?? DeviceOrientation.values,
      );
    }

    if (widget.displayFullScreenAfterInit) {}
  }

  @override
  void dispose() {
    m3u8Clean();
    controller.dispose();
    controlBarAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: fullScreen
          ? MediaQuery.of(context).size.calculateAspectRatio()
          : widget.aspectRatio,
      child: controller.value.isInitialized
          ? Stack(
              children: <Widget>[
                GestureDetector(
                  onTap: () {
                    toggleControls();
                    removeOverlay();
                  },
                  onDoubleTap: () {
                    togglePlay();
                    removeOverlay();
                  },
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: Container(
                          foregroundDecoration: BoxDecoration(
                            color: showMenu
                                ? Colors.black.withValues(alpha: 0.2)
                                : Colors.transparent,
                          ),
                          child: VideoPlayer(
                            controller,
                          )),
                    ),
                  ),
                ),
                ...videoBuiltInChildren(),
              ],
            )
          : VideoLoading(
              loadingStyle: widget.videoLoadingStyle, thumbUrl: widget.url),
    );
  }

  List<Widget> videoBuiltInChildren() {
    return [
      actionBar(),
      liveDirectButton(),
      bottomBar(),
      bufferStatus(),
      Visibility(
        visible: !showMenu,
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              children: [
                fullScreen
                    ? const SizedBox.shrink()
                    : Align(
                        alignment: Alignment.bottomCenter,
                        child: SizedBox(
                          height: 2,
                          child: VideoProgressIndicator(
                            controller,
                            allowScrubbing: false,
                            colors: const VideoProgressColors(
                              playedColor: Color.fromARGB(255, 206, 3, 3),
                              bufferedColor: Color.fromARGB(169, 77, 68, 68),
                              backgroundColor:
                                  Color.fromARGB(27, 255, 255, 255),
                            ),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      )
      // m3u8List(),
    ];
  }

  /// Video player ActionBar
  Widget actionBar() {
    return Visibility(
      visible: showMenu,
      child: Align(
        alignment: Alignment.topCenter,
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            width: MediaQuery.of(context).size.width,
            padding: widget.videoStyle.actionBarPadding ??
                const EdgeInsets.symmetric(
                  horizontal: 0.0,
                  vertical: 0.0,
                ),
            alignment: Alignment.topRight,
            color: widget.videoStyle.actionBarBgColor,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                InkWell(
                  onTap: () => showSettingsDialog(context),
                  child: const Padding(
                    padding: EdgeInsets.only(top: 8.0, left: 8.0, bottom: 8.0),
                    child: Icon(
                      Icons.settings,
                      color: Colors.white,
                      size: 30.0,
                    ),
                  ),
                ),
                SizedBox(
                  width: widget.videoStyle.qualityButtonAndFullScrIcoSpace,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget bufferStatus() {
    // final bufferedDuration = controller.value.buffered.isNotEmpty
    //     ? controller.value.buffered.last.end.inSeconds
    //     : 0;
    // final totalDuration = controller.value.duration.inSeconds;
    // //get the bitrate from the video controller
    // var bitrate = 800;
    // final bufferedSizeKB = (bufferedDuration * bitrate) / 8;
    // final totalSizeKB = (totalDuration * bitrate) / 8;

    return Visibility(
      visible: controller.value.isBuffering,
      child: const Center(
        child: Text(
          // 'Buffering: ${bufferedSizeKB.toStringAsFixed(0)} KB of ${totalSizeKB.toStringAsFixed(0)} KB',
          'ভিডিও লোড হচ্ছে...',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16.0,
          ),
        ),
      ),
    );
  }

  /// Video player BottomBar
  Widget bottomBar() {
    return Visibility(
      visible: showMenu,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: PlayerBottomBar(
          fullScreen: fullScreen,
          controller: controller,
          videoSeek: videoSeek ?? '00:00:00',
          videoDuration: videoDuration ?? '00:00:00',
          videoStyle: widget.videoStyle,
          showBottomBar: showMenu,
          onPlayButtonTap: () => togglePlay(),
          onFastForward: (value) {
            widget.onFastForward?.call(value);
          },
          onRewind: (value) {
            widget.onRewind?.call(value);
          },
        ),
      ),
    );
  }

  /// Video player live direct button
  Widget liveDirectButton() {
    return Visibility(
      visible: widget.videoStyle.showLiveDirectButton && showMenu,
      child: Align(
        alignment: Alignment.topLeft,
        child: IntrinsicWidth(
          child: InkWell(
            onTap: () {
              controller.seekTo(controller.value.duration).then((value) {
                widget.onLiveDirectTap?.call(controller.value);
                controller.play();
              });
            },
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 14.0,
                vertical: 14.0,
              ),
              margin: const EdgeInsets.only(left: 9.0),
              child: Row(
                children: [
                  Container(
                    width: widget.videoStyle.liveDirectButtonSize,
                    height: widget.videoStyle.liveDirectButtonSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isAtLivePosition
                          ? widget.videoStyle.liveDirectButtonColor
                          : widget.videoStyle.liveDirectButtonDisableColor,
                    ),
                  ),
                  const SizedBox(width: 8.0),
                  Text(
                    widget.videoStyle.liveDirectButtonText ?? 'Live',
                    style: widget.videoStyle.liveDirectButtonTextStyle ??
                        const TextStyle(color: Colors.white, fontSize: 16.0),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Video quality list
  Widget m3u8List() {
    RenderBox? renderBox =
        videoQualityKey.currentContext?.findRenderObject() as RenderBox?;
    var offset = renderBox?.localToGlobal(Offset.zero);
    return VideoQualityPicker(
      videoData: m3u8UrlList,
      videoStyle: widget.videoStyle,
      showPicker: m3u8Show,
      positionRight: (renderBox?.size.width ?? 0.0) / 3,
      positionTop: (offset?.dy ?? 0.0) + 35.0,
      onQualitySelected: (data) {
        if (data.dataQuality != m3u8Quality) {
          setState(() {
            m3u8Quality = data.dataQuality ?? m3u8Quality;
          });
          onSelectQuality(data);
          print(
              "--- Quality select ---\nquality : ${data.dataQuality}\nlink : ${data.dataURL}");
        }
        setState(() {
          m3u8Show = false;
        });
        removeOverlay();
      },
      selectedQuality: m3u8Quality,
    );
  }

  void urlCheck(String url) {
    final netRegex = RegExp(RegexResponse.regexHTTP);
    final isNetwork = netRegex.hasMatch(url);
    final uri = Uri.parse(url);

    print("Parsed url data end : ${uri.pathSegments.last}");
    if (isNetwork) {
      setState(() {
        isOffline = false;
      });
      if (uri.pathSegments.last.endsWith("mkv")) {
        setState(() {
          playType = "MKV";
        });
        print("urlEnd : mkv");
        widget.onPlayingVideo?.call("MKV");

        videoControlSetup(url);

        if (widget.allowCacheFile) {
          FileUtils.cacheFileToLocalStorage(
            url,
            fileExtension: 'mkv',
            headers: widget.headers,
            onSaveCompleted: (file) {
              widget.onCacheFileCompleted?.call(file != null ? [file] : null);
            },
            onSaveFailed: widget.onCacheFileFailed,
          );
        }
        log("urlEnd===============>: $playType");
      } else if (uri.pathSegments.last.endsWith("mp4")) {
        setState(() {
          playType = "MP4";
        });
        print("urlEnd: $playType");
        widget.onPlayingVideo?.call("MP4");

        videoControlSetup(url);

        if (widget.allowCacheFile) {
          FileUtils.cacheFileToLocalStorage(
            url,
            fileExtension: 'mp4',
            headers: widget.headers,
            onSaveCompleted: (file) {
              widget.onCacheFileCompleted?.call(file != null ? [file] : null);
            },
            onSaveFailed: widget.onCacheFileFailed,
          );
        }
        log("urlEnd===============>: $playType");
      } else if (uri.pathSegments.last.endsWith('webm')) {
        setState(() {
          playType = "WEBM";
        });
        print("urlEnd: $playType");
        widget.onPlayingVideo?.call("WEBM");

        videoControlSetup(url);

        if (widget.allowCacheFile) {
          FileUtils.cacheFileToLocalStorage(
            url,
            fileExtension: 'webm',
            headers: widget.headers,
            onSaveCompleted: (file) {
              widget.onCacheFileCompleted?.call(file != null ? [file] : null);
            },
            onSaveFailed: widget.onCacheFileFailed,
          );
        }
        log("urlEnd===============>: $playType");
      } else if (uri.pathSegments.last.endsWith("m3u8")) {
        setState(() {
          playType = "HLS";
        });
        widget.onPlayingVideo?.call("M3U8");

        print("urlEnd: M3U8");
        videoControlSetup(url);
        getM3U8(url);
      } else {
        print("urlEnd: null");
        videoControlSetup(url);
        getM3U8(url);
      }
      print("--- Current Video Status ---\noffline : $isOffline");
    } else {
      setState(() {
        isOffline = true;
        print(
            "--- Current Video Status ---\noffline : $isOffline \n --- :3 Done url check ---");
      });

      videoControlSetup(url);
    }
  }

  /// M3U8 Data Setup
  void getM3U8(String videoUrl) {
    if (m3u8UrlList.isNotEmpty) {
      print("${m3u8UrlList.length} : data start clean");
      m3u8Clean();
    }
    print("---- m3u8 fitch start ----\n$videoUrl\n--- please wait –––");
    m3u8Video(videoUrl);
  }

  Future<M3U8s?> m3u8Video(String? videoUrl) async {
    m3u8UrlList.add(M3U8Data(dataQuality: "Auto", dataURL: videoUrl));

    RegExp regExp = RegExp(
      RegexResponse.regexM3U8Resolution,
      caseSensitive: false,
      multiLine: true,
    );

    if (m3u8Content != null) {
      setState(() {
        print("--- HLS Old Data ----\n$m3u8Content");
        m3u8Content = null;
      });
    }

    if (m3u8Content == null && videoUrl != null) {
      http.Response response =
          await http.get(Uri.parse(videoUrl), headers: widget.headers);
      if (response.statusCode == 200) {
        m3u8Content = utf8.decode(response.bodyBytes);

        List<File> cachedFiles = [];
        int index = 0;

        List<RegExpMatch> matches =
            regExp.allMatches(m3u8Content ?? '').toList();
        print(
            "--- HLS Data ----\n$m3u8Content \nTotal length: ${m3u8UrlList.length} \nFinish!!!");

        for (RegExpMatch regExpMatch in matches) {
          String quality = (regExpMatch.group(1)).toString();
          String sourceURL = (regExpMatch.group(3)).toString();
          final netRegex = RegExp(RegexResponse.regexHTTP);
          final netRegex2 = RegExp(RegexResponse.regexURL);
          final isNetwork = netRegex.hasMatch(sourceURL);
          final match = netRegex2.firstMatch(videoUrl);
          String url;
          if (isNetwork) {
            url = sourceURL;
          } else {
            print(
                'Match: ${match?.pattern} --- ${match?.groupNames} --- ${match?.input}');
            final dataURL = match?.group(0);
            url = "$dataURL$sourceURL";
            print("--- HLS child url integration ---\nChild url :$url");
          }
          for (RegExpMatch regExpMatch2 in matches) {
            String audioURL = (regExpMatch2.group(1)).toString();
            final isNetwork = netRegex.hasMatch(audioURL);
            final match = netRegex2.firstMatch(videoUrl);
            String auURL = audioURL;

            if (!isNetwork) {
              print(
                  'Match: ${match?.pattern} --- ${match?.groupNames} --- ${match?.input}');
              final auDataURL = match!.group(0);
              auURL = "$auDataURL$audioURL";
              print("Url network audio  $url $audioURL");
            }

            audioList.add(AudioModel(url: auURL));
            print(audioURL);
          }

          String audio = "";
          print("-- Audio ---\nAudio list length: ${audio.length}");
          if (audioList.isNotEmpty) {
            audio =
                """#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="audio-medium",NAME="audio",AUTOSELECT=YES,DEFAULT=YES,CHANNELS="2",
                  URI="${audioList.last.url}"\n""";
          } else {
            audio = "";
          }

          if (widget.allowCacheFile) {
            try {
              var file = await FileUtils.cacheFileUsingWriteAsString(
                contents:
                    """#EXTM3U\n#EXT-X-INDEPENDENT-SEGMENTS\n$audio#EXT-X-STREAM-INF:CLOSED-CAPTIONS=NONE,BANDWIDTH=1469712,
                  RESOLUTION=$quality,FRAME-RATE=30.000\n$url""",
                quality: quality,
                videoUrl: url,
              );

              cachedFiles.add(file);

              if (index < matches.length) {
                index++;
              }

              if (widget.allowCacheFile && index == matches.length) {
                widget.onCacheFileCompleted
                    ?.call(cachedFiles.isEmpty ? null : cachedFiles);
              }
            } catch (e) {
              print("Couldn't write file: $e");
              widget.onCacheFileFailed?.call(e);
            }
          }
          //need to add the video quality to the list by the quality order.and auto quality should be the first one.
          //  var orderBasedSerializedList = m3u8UrlList.map((e) => e.dataQuality).toList();
          m3u8UrlList.add(M3U8Data(dataQuality: quality, dataURL: url));
        }
        M3U8s m3u8s = M3U8s(m3u8s: m3u8UrlList);

        print(
            "--- m3u8 File write --- ${m3u8UrlList.map((e) => e.dataQuality == e.dataURL).toList()} --- length : ${m3u8UrlList.length} --- Success");
        return m3u8s;
      }
    }

    return null;
  }

// Init video controller
  void videoControlSetup(String? url) async {
    videoInit(url);
    controller.addListener(listener);
    if (widget.autoPlayVideoAfterInit) {
      controller.play();
    }
    widget.onVideoInitCompleted?.call(controller);
  }

// Video listener
  void listener() async {
    if (widget.videoStyle.showLiveDirectButton) {
      if (controller.value.position != controller.value.duration) {
        if (isAtLivePosition) {
          setState(() {
            isAtLivePosition = false;
          });
        }
      } else {
        if (!isAtLivePosition) {
          setState(() {
            isAtLivePosition = true;
          });
        }
      }
    }

    if (controller.value.isInitialized && controller.value.isPlaying) {
      if (!await WakelockPlus.enabled) {
        await WakelockPlus.enable();
      }

      setState(() {
        videoDuration = controller.value.duration.convertDurationToString();
        videoSeek = controller.value.position.convertDurationToString();
        videoSeekSecond = controller.value.position.inSeconds.toDouble();
        videoDurationSecond = controller.value.duration.inSeconds.toDouble();
      });
    } else {
      if (await WakelockPlus.enabled) {
        await WakelockPlus.disable();
        setState(() {});
      }
    }
  }

  void createHideControlBarTimer() {
    clearHideControlBarTimer();
    showTime = Timer(const Duration(milliseconds: 5000), () {
      // if (controller != null && controller.value.isPlaying) {
      if (controller.value.isPlaying) {
        if (showMenu) {
          setState(() {
            showMenu = false;
            m3u8Show = false;
            controlBarAnimationController.reverse();

            widget.onShowMenu?.call(showMenu, m3u8Show);
            removeOverlay();
          });
        }
      }
    });
  }

  void clearHideControlBarTimer() {
    showTime?.cancel();
  }

  void toggleControls() {
    clearHideControlBarTimer();

    if (!showMenu) {
      setState(() {
        showMenu = true;
      });
      widget.onShowMenu?.call(showMenu, m3u8Show);

      createHideControlBarTimer();
    } else {
      setState(() {
        m3u8Show = false;
        showMenu = false;
      });

      widget.onShowMenu?.call(showMenu, m3u8Show);
    }
    // setState(() {
    if (showMenu) {
      controlBarAnimationController.forward();
    } else {
      controlBarAnimationController.reverse();
    }
    // });
  }

  void togglePlay() {
    createHideControlBarTimer();
    if (controller.value.isPlaying) {
      controller.pause().then((_) {
        widget.onPlayButtonTap?.call(controller.value.isPlaying);
      });
    } else {
      controller.play().then((_) {
        widget.onPlayButtonTap?.call(controller.value.isPlaying);
      });
    }
    setState(() {});
  }

  void videoInit(String? url) {
    if (isOffline == false) {
      print(
          "--- Player status ---\nplay url : $url\noffline : $isOffline\n--- start playing –––");

      if (playType == "MP4" || playType == "WEBM") {
        // Play MP4 and WEBM video
        controller = VideoPlayerController.networkUrl(
          Uri.parse(url!),
          formatHint: VideoFormat.other,
          httpHeaders: widget.headers ?? const <String, String>{},
          closedCaptionFile: widget.closedCaptionFile,
          videoPlayerOptions: widget.videoPlayerOptions,
        )..initialize().then((value) => seekToLastPlayingPosition);
      } else if (playType == "MKV") {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(url!),
          formatHint: VideoFormat.dash,
          httpHeaders: widget.headers ?? const <String, String>{},
          closedCaptionFile: widget.closedCaptionFile,
          videoPlayerOptions: widget.videoPlayerOptions,
        )..initialize().then((value) => seekToLastPlayingPosition);
      } else if (playType == "HLS") {
        controller = VideoPlayerController.networkUrl(
          Uri.parse(url!),
          formatHint: VideoFormat.hls,
          httpHeaders: widget.headers ?? const <String, String>{},
          closedCaptionFile: widget.closedCaptionFile,
          videoPlayerOptions: widget.videoPlayerOptions,
        )..initialize().then((_) {
            setState(() => hasInitError = false);
            seekToLastPlayingPosition();
          }).catchError((e) {
            setState(() => hasInitError = true);
          });
      }
    } else {
      print(
          "--- Player status ---\nplay url : $url\noffline : $isOffline\n--- start playing –––");
      hideQualityList = true;
      controller = VideoPlayerController.file(
        File(url!),
        closedCaptionFile: widget.closedCaptionFile,
        videoPlayerOptions: widget.videoPlayerOptions,
      )..initialize().then((value) {
          setState(() => hasInitError = false);
          seekToLastPlayingPosition();
        }).catchError((e) {
          setState(() => hasInitError = true);
        });
    }
  }

  void _navigateLocally(BuildContext context) async {
    if (!fullScreen) {
      if (ModalRoute.of(context)?.willHandlePopInternally ?? false) {
        Navigator.of(context).pop();
      }
      return;
    }
  }

  void onSelectQuality(M3U8Data data) async {
    lastPlayedPos = await controller.position;

    if (controller.value.isPlaying) {
      await controller.pause();
    }

    if (data.dataQuality == "Auto") {
      videoControlSetup(data.dataURL);
    } else {
      try {
        String text;
        var file = await FileUtils.readFileFromPath(
            videoUrl: data.dataURL ?? '', quality: data.dataQuality ?? '');
        if (file != null) {
          print("Start reading file");
          text = await file.readAsString();
          print("Video file data: $text");

          if (data.dataURL != null) {
            playLocalM3U8File(data.dataURL!);
          } else {
            print('Play ${data.dataQuality} m3u8 video file failed');
          }
          // videoControlSetup(file);
        }
      } catch (e) {
        print("Couldn't read file ${data.dataQuality}: $e");
      }
    }
  }

  void playLocalM3U8File(String url) {
    controller.dispose();
    controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      closedCaptionFile: widget.closedCaptionFile,
      videoPlayerOptions: widget.videoPlayerOptions,
    )..initialize().then((_) {
        setState(() => hasInitError = false);
        seekToLastPlayingPosition();
        controller.play();
      }).catchError((e) {
        setState(() => hasInitError = true);
        print('Init local file error $e');
      });

    controller.addListener(listener);
    controller.play();
  }

  void m3u8Clean() async {
    print('Video list length: ${m3u8UrlList.length}');
    for (int i = 2; i < m3u8UrlList.length; i++) {
      try {
        var file = await FileUtils.readFileFromPath(
            videoUrl: m3u8UrlList[i].dataURL ?? '',
            quality: m3u8UrlList[i].dataQuality ?? '');
        var exists = await file?.exists();
        if (exists ?? false) {
          await file?.delete();
          print("Delete success $file");
        }
      } catch (e) {
        print("Couldn't delete file $e");
      }
    }
    try {
      print("Cleaning audio m3u8 list");
      audioList.clear();
      print("Cleaning audio m3u8 list completed");
    } catch (e) {
      print("Audio list clean error $e");
    }
    audioList.clear();
    try {
      print("Cleaning m3u8 data list");
      m3u8UrlList.clear();
      print("Cleaning m3u8 data list completed");
    } catch (e) {
      print("m3u8 video list clean error $e");
    }
  }

  void showOverlay() {
    setState(() {
      overlayEntry = OverlayEntry(
        builder: (_) => m3u8List(),
      );
      Overlay.of(context).insert(overlayEntry!);
    });
  }

  void showResolutionDialog(BuildContext context) {
    showModalBottomSheet(
      backgroundColor: Colors.transparent,
      context: context,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.only(top: 10.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10.0),
              topRight: Radius.circular(10.0),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(top: 10.0),
                      width: 70,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Text(''),
                    )),
                VideoQualityPicker(
                  videoData: m3u8UrlList,
                  videoStyle: widget.videoStyle,
                  showPicker: true,
                  onQualitySelected: (data) {
                    if (data.dataQuality != m3u8Quality) {
                      setState(() {
                        m3u8Quality = data.dataQuality ?? m3u8Quality;
                      });
                      onSelectQuality(data);
                      print(
                          "--- Quality select ---\nquality : ${data.dataQuality}\nlink : ${data.dataURL}");
                    }
                    setState(() {
                      m3u8Show = false;
                    });
                    // removeOverlay();
                    Navigator.pop(context);
                  },
                  selectedQuality: m3u8Quality,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void showPlayBackSpeed(BuildContext context) {
    showModalBottomSheet(
      backgroundColor: Colors.transparent,
      context: context,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.only(top: 10.0),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(10.0),
              topRight: Radius.circular(10.0),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(top: 10.0),
                      width: 70,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Text(''),
                    )),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                      playbackSpeeds.length,
                      (index) => ListTile(
                            leading: Icon(
                              Icons.check,
                              color: playbackSpeeds[index] == playbackSpeed
                                  ? Colors.green
                                  : Colors.transparent,
                              size: 20,
                            ),
                            title: Text(
                              playbackSpeeds[index] == 1.0
                                  ? 'Normal'
                                  : '${playbackSpeeds[index]}x',
                              style: const TextStyle(fontSize: 14),
                            ),
                            onTap: () {
                              setState(() {
                                playbackSpeed = playbackSpeeds[index];
                              });
                              onPlayBackSpeedChange(
                                  setPlaybackSpeed: playbackSpeed);
                              Navigator.pop(context);
                            },
                          )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void onPlayBackSpeedChange({required double setPlaybackSpeed}) {
    if (controller.value.isPlaying) {
      controller.pause();
      controller.setPlaybackSpeed(setPlaybackSpeed);
      controller.play();
    } else {
      controller.setPlaybackSpeed(setPlaybackSpeed);
      controller.play();
    }
  }

  Future showSettingsDialog(BuildContext context) {
    return showModalBottomSheet(
        backgroundColor: Colors.transparent,
        context: context,
        builder: (context) {
          duration = controller.value.duration;
          return Container(
            margin: const EdgeInsets.only(top: 10.0),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(10.0),
                topRight: Radius.circular(10.0),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                    onTap: () {
                      Navigator.pop(context);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(top: 10.0),
                      width: 70,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10.0),
                      ),
                      child: const Text(''),
                    )),
                if (!hideQualityList)
                  ListTile(
                    leading: const Icon(Icons.tune),
                    title: const Text(
                      "Quality",
                      style: TextStyle(fontSize: 14.0, color: Colors.black),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                            m3u8Quality.toString() == 'Auto'
                                ? 'Auto'
                                : '${m3u8Quality.toString().split('x').last}p',
                            style: const TextStyle(
                                fontSize: 12.0, color: Colors.black54)),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 15,
                        ),
                      ],
                    ),
                    onTap: () {
                      Navigator.pop(context);
                      showResolutionDialog(context);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.slow_motion_video),
                  title: const Text(
                    "Speed",
                    style: TextStyle(fontSize: 14.0, color: Colors.black),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        playbackSpeed == 1.0 ? 'Normal' : '${playbackSpeed}x',
                        style: const TextStyle(
                            fontSize: 12.0, color: Colors.black54),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios,
                        size: 15,
                      ),
                    ],
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    showPlayBackSpeed(context);
                  },
                ),
                ListTile(
                  leading: Icon(
                    loop ? Icons.repeat_one : Icons.repeat,
                  ),
                  title: const Text(
                    "Loop Video",
                    style: TextStyle(fontSize: 14.0, color: Colors.black),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        loop ? 'On' : 'Off',
                        style: const TextStyle(
                            fontSize: 12.0, color: Colors.black54),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 15),
                    ],
                  ),
                  onTap: () {
                    loop = !loop;
                    if (controller.value.isPlaying) {
                      controller.pause();
                      controller.setLooping(loop);
                      controller.play();
                    } else {
                      controller.setLooping(loop);
                    }
                    if (loop) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Video loop is on"),
                          duration: Duration(seconds: 3),
                          backgroundColor: Colors.grey,
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text("Video loop is off"),
                        duration: Duration(seconds: 3),
                        backgroundColor: Colors.grey,
                      ));
                    }
                    Navigator.pop(context);
                  },
                ),
              ],
            ),
          );
        });
  }

  void removeOverlay() {
    setState(() {
      overlayEntry?.remove();
      overlayEntry = null;
    });
  }

  void seekToLastPlayingPosition() {
    if (lastPlayedPos != null) {
      controller.seekTo(lastPlayedPos!);
      widget.onVideoInitCompleted?.call(controller);
      lastPlayedPos = null;
    }
  }
}
