import 'package:flutter/material.dart';
import 'package:ns_player/ns_player.dart';
import 'package:ns_player/src/model/m3u8.dart';

class VideoQualityPicker extends StatelessWidget {
  final List<M3U8Data> videoData;
  final bool showPicker;
  final double? positionRight;
  final double? positionTop;
  final double? positionLeft;
  final double? positionBottom;
  final VideoStyle videoStyle;
  final String selectedQuality;
  final void Function(M3U8Data data)? onQualitySelected;

  const VideoQualityPicker({
    super.key,
    required this.videoData,
    this.videoStyle = const VideoStyle(),
    this.showPicker = false,
    this.positionRight,
    this.positionTop,
    this.onQualitySelected,
    this.positionLeft,
    this.positionBottom,
    required this.selectedQuality,
  });

  @override
  Widget build(BuildContext context) {
    // videoData.sort((a, b) {
    //   if (a.dataQuality == 'Auto') {
    //     return -1;
    //   } else if (b.dataQuality == 'Auto') {
    //     return 1;
    //   } else {
    //     return int.parse(a.dataQuality!.split('x').last)
    //         .compareTo(int.parse(b.dataQuality!.split('x').last));
    //   }
    // });
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          videoData.length,
          (index) => ListTile(
            leading: Icon(
              Icons.check,
              color: videoData[index].dataQuality == selectedQuality
                  ? Colors.green
                  : Colors.transparent,
              size: 20,
            ),
            title: Text(
                videoData[index].dataQuality.toString() == 'Auto'
                    ? 'Auto (Recommended)'
                    : '${videoData[index].dataQuality.toString().split('x').last}p',
                style: const TextStyle(fontSize: 14)),
            onTap: () {
              onQualitySelected?.call(videoData[index]);
            },
          ),
        ),
      ),
    );
  }
}
