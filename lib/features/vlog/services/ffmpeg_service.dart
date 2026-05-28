import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class FFmpegService {

  /// photos to vlog (mp4)
  Future<String> createVideoFromImages({
    required List<String> imagePaths,
    int secondsPerImage = 4,
  }) async {

    final dir = await getApplicationDocumentsDirectory();

    final outputPath = '${dir.path}/vlog_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // build input pattern

    final tempDir = Directory('${dir.path}/frames');
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }

    // copy to ffmpeg readable format
    for (int i = 0; i < imagePaths.length; i++) {
      final file = File(imagePaths[i]);
      final frameName = 'img_${i.toString().padLeft(4, '0')}.jpg';
      await file.copy('${tempDir.path}/$frameName');
    }

    // ffmpeg command
    final command =
        '-y -framerate 1/$secondsPerImage -start_number 0 '
        '-i "${tempDir.path}/img_%04d.jpg" '
        '-c:v mpeg4 -pix_fmt yuv420p '
        '"$outputPath"';

    final session = await FFmpegKit.execute(command);

    final returnCode = await session.getReturnCode();

    if (!ReturnCode.isSuccess(returnCode)) {
      throw Exception('FFmpeg failed: $returnCode');
    }

    return outputPath;
  }
}