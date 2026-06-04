import 'dart:io';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:path_provider/path_provider.dart';

class FFmpegService {

  String _q(String path) => '"${path.replaceAll('"', r'\"')}"';

  String _buildSingleFrameCommand({
    required String framePath,
    required int secondsPerImage,
    required String outputPath,
    required String? bgmPath,
  }) {
    // bgm command
    final audioInput = bgmPath == null 
        ? <String>[] 
        : [
            '-stream_loop -1',
            '-i ${_q(bgmPath)}',
          ];
    final audioArgs = bgmPath == null
        ? <String>[]
        : [
            '-map 0:v',
            '-map 1:a',
            '-c:a aac',
            '-shortest',
          ];

    return [
      '-y',
      '-loop 1',
      '-t $secondsPerImage',
      '-i ${_q(framePath)}',
      ...audioInput,
      '-vf "fps=30,format=yuv420p"',
      '-c:v mpeg4',
      '-pix_fmt yuv420p',
      ...audioArgs,
      _q(outputPath),
    ].join(' ');
  }

  String _buildTransitionCommand({
    required List<String> framePath,
    required int secondsPerImage,
    required double transitionSeconds,
    required String outputPath,
    required String? bgmPath,
  }) {
    final input = <String>[];

    // frame command
    for (final path in framePath) {
      input.add('-loop 1');
      input.add('-t $secondsPerImage');
      input.add('-i ${_q(path)}');
    }

    // bgm command
    final audioInputIndex = framePath.length;

    if (bgmPath != null) {
      input.add('-stream_loop -1');
      input.add('-i ${_q(bgmPath)}');
    }

    // filter
    final filters = <String>[];

    for (int i = 0; i < framePath.length; i++) {
      filters.add(
        '[$i:v]fps=30,format=yuv420p,settb=AVTB[v$i]',
      );
    }

    var previous = 'v0';

    // fade transition
    for (int i = 1; i < framePath.length; i++) {
      final output = i == framePath.length - 1 ? 'vout' : 'x$i';
      final offset = (secondsPerImage - transitionSeconds) * i;

      filters.add(
        '[$previous][v$i]'
        'xfade=transition=fade:duration=$transitionSeconds:offset=$offset'
        '[$output]',
      );

      previous = output;
    }

    final audioArgs = bgmPath == null
        ? <String>[]
        : [
            '-map "[vout]"',
            '-map $audioInputIndex:a',
            '-c:a aac',
            '-shortest',
          ];

    return [
      '-y',
      ...input,
      '-filter_complex "${filters.join(';')}"',
      if (bgmPath == null) '-map "[vout]"',
      ...audioArgs,
      '-c:v mpeg4',
      '-pix_fmt yuv420p',
      _q(outputPath),
    ].join(' ');
  }

  /// photos to vlog (mp4)
  Future<String> createVideoFromImages({
    required List<String> imagePaths,
    int secondsPerImage = 3,
    double transitionSeconds = 0.6,
    String? bgmPath,
  }) async {
    
    final dir = await getApplicationDocumentsDirectory();

    final outputPath = '${dir.path}/vlog_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // build input pattern
    final tempDir = Directory('${dir.path}/frames');

    // clean folder
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    
    await tempDir.create(recursive: true);

    try {
      final copiedFramePaths = <String>[];
      
      for (int i = 0; i < imagePaths.length; i++) {
        final file = File(imagePaths[i]);
        final frameName = 'img_${i.toString().padLeft(4, '0')}.jpg';
        final copiedPath = '${tempDir.path}/$frameName';

        await file.copy(copiedPath);
        copiedFramePaths.add(copiedPath);
      }

      if (copiedFramePaths.isEmpty) {
        throw Exception('No frame to generate video.');
      }

      final command = copiedFramePaths.length == 1
          ? _buildSingleFrameCommand(
              framePath: copiedFramePaths.first, 
              secondsPerImage: secondsPerImage, 
              outputPath: outputPath,
              bgmPath: bgmPath,
            )
          : _buildTransitionCommand(
              framePath: copiedFramePaths, 
              secondsPerImage: secondsPerImage, 
              transitionSeconds: transitionSeconds, 
              outputPath: outputPath,
              bgmPath: bgmPath,
            );

      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode)) {
        throw Exception('FFmpeg failed: $returnCode');
      }

      return outputPath;
    } finally {

      // clear frames
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    }
  }
}