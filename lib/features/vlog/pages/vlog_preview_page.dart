import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner/core/providers/database_provider.dart';
import 'package:trip_planner/features/roi/providers/roi_provider.dart';
import 'package:gal/gal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/vlog_repository.dart';
import '../services/frame_builder.dart';
import '../services/ffmpeg_service.dart';

class _FrameArgs {
  final String userImagePath;
  final String? referenceImagePath;
  final String title;

  const _FrameArgs({
    required this.userImagePath,
    required this.referenceImagePath,
    required this.title,
  });
}

class _BgmOption {
  final String label;
  final String? path;
  final bool isAddAction;

  const _BgmOption({
    required this.label,
    this.path,
    this.isAddAction = false,
  });
}

Future<Uint8List> _buildFrameInIsolate(_FrameArgs args) {
  return FrameBuilder().buildCompareFrame(
    userImagePath: args.userImagePath,
    referenceImagePath: args.referenceImagePath,
    title: args.title,
  );
}

class VlogPreviewPage extends ConsumerStatefulWidget {

    const VlogPreviewPage({super.key});

    @override
    ConsumerState<VlogPreviewPage> createState() => _VlogPreviewPageState();
}

class _VlogPreviewPageState extends ConsumerState<VlogPreviewPage> {

  String? selectedRoiId;
  String? selectedBgmPath;

  final List<_BgmOption> customBgmOptions = [];

  List<_BgmOption> get bgmOptions => [
    const _BgmOption(label: 'No BGM', path: null),
    const _BgmOption(label: 'Default BGM', path: 'default'),
    ...customBgmOptions,
    const _BgmOption(label: '+ Add BGM', isAddAction: true),
  ];

  bool isGenerating = false;
  
  String? outputVideoPath;

  Future<String> prepareDefaultBgm() async {
    const assetPath = 'lib/features/vlog/audio/Carefree.mp3';

    final bytes = await rootBundle.load(assetPath);
    final appDir = await getApplicationDocumentsDirectory();
    final bgmDir = Directory(p.join(appDir.path, 'bgm'));

    if (!await bgmDir.exists()) {
      await bgmDir.create(recursive: true);
    }

    final outputPath = p.join(bgmDir.path, 'default_carefree.mp3');
    final outputFile = File(outputPath);

    if (!await outputFile.exists()) {
      await outputFile.writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
    }

    return outputPath;
  }

  Future<void> addBgm() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'm4a', 'aac'],
    );

    if (result == null || result.files.single.path == null) return;

    final source = File(result.files.single.path!);
    final appDir = await (getApplicationDocumentsDirectory());
    final bgmDir = Directory(p.join(appDir.path, 'bgm'));

    if (!await bgmDir.exists()) {
      await bgmDir.create(recursive: true);
    }

    final extension = p.extension(source.path).isEmpty
        ? '.mp3'
        : p.extension(source.path);

    final fileName = '${DateTime.now().millisecondsSinceEpoch}$extension';
    final savedPath = p.join(bgmDir.path, fileName);

    await source.copy(savedPath);

    setState(() {
      customBgmOptions.add(
        _BgmOption(
          label: p.basename(source.path),
          path: savedPath,
        ),
      );
      selectedBgmPath = savedPath;
    });
  }

  Future<void> generateVlog() async {

    setState(() {
      isGenerating = true;
    });

    try {

      final roiId = selectedRoiId;
      if (roiId == null) {
        setState(() {
          isGenerating = false;
        });
        return;
      }

      final db = ref.read(databaseProvider);
      final repository = VlogRepository(db);

      // get image paths by ROIs
      final frameSource = await repository.getVlogFramesByRoi(roiId);

      // check image paths
      if (frameSource.isEmpty) {
        if (!mounted) return; 
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No photos found in this ROI.'),
          ),
        );

        setState(() {
          isGenerating = false;
        });

        return;
      }

      // build frames in a dedicated temp dir so we can clean up afterwards.
      final framesTempDir = await Directory.systemTemp.createTemp('vlog_frames_');
      final framePaths = <String>[];

      for (int i = 0; i < frameSource.length; i++) {
        final source = frameSource[i];

        // compute() must use a top-level helper rather than Isolate.run with
        // a closure: a closure created inside this instance method silently
        // captures `this` (the State) via its lexical context, dragging the
        // entire widget tree across the isolate boundary, which fails the
        // sendability check.
        final bytes = await compute(_buildFrameInIsolate, _FrameArgs(
          userImagePath: source.userImagePath,
          referenceImagePath: source.referenceImagePath,
          title: source.poiName,
        ));

        final tempFile = File('${framesTempDir.path}/frame_$i.jpg');
        await tempFile.writeAsBytes(bytes);
        framePaths.add(tempFile.path);
      }

      // select init bgm
      final bgmPath = selectedBgmPath == 'default'
          ? await prepareDefaultBgm()
          : selectedBgmPath;

      // generate mp4
      final ffmpeg = FFmpegService();
      final videoPath = await ffmpeg.createVideoFromImages(
        imagePaths: framePaths,
        secondsPerImage: 3,
        transitionSeconds: 0.6,
        bgmPath: bgmPath,
      );

      // ffmpeg has copied frames into its own dir; we can drop ours now.
      try {
        await framesTempDir.delete(recursive: true);
      } catch (_) {}

      // store to photo album
      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        await Gal.requestAccess(toAlbum: true);
      }

      await Gal.putVideo(videoPath, album: 'Trip Planner');

      // clean useless video
      await File(videoPath).delete();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vlog saved to gallery'),
        ),
      );

      if (!mounted) return;

      setState(() {
        outputVideoPath = videoPath;
      });

    } catch (e) {

      debugPrint(e.toString());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to Generate Vlog: $e'),
        ),
      );
    }

    setState(() {
      isGenerating = false;
    });
  }

  @override
  Widget build(BuildContext context) {

    final roisAsync = ref.watch(allRoisProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vlog Preview'),
      ),
      body: roisAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (rois) {
          if (rois.isEmpty) {
            return const Center(
              child: Text('Create an ROI first.'),
            );
          }

          selectedRoiId ??= rois.first.id;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedRoiId,
                  decoration: const InputDecoration(
                    labelText: 'ROI',
                  ),
                  items: rois.map((roi) {
                    return DropdownMenuItem(
                      value: roi.id,
                      child: Text(roi.name),
                    );
                  }).toList(),
                  onChanged: (value) {
                    setState(() {
                      selectedRoiId = value;
                      outputVideoPath = null;
                    });
                  },
                ),

                const SizedBox(height: 20),

                DropdownButtonFormField<String?>(
                  initialValue: selectedBgmPath,
                  decoration: const InputDecoration(
                    labelText: 'BGM',
                  ),
                  items: bgmOptions.map((option) {
                    return DropdownMenuItem<String?>(
                      value: option.isAddAction ? '__add_bgm__' : option.path,
                      child: Text(option.label),
                    );
                  }).toList(),
                  onChanged: isGenerating
                      ? null
                      : (value) async {
                          if (value == '__add_bgm__') {
                            await addBgm();
                            return;
                          }

                          setState(() {
                            selectedBgmPath = value;
                          });
                        },
                ),

                const SizedBox(height: 20),

                ElevatedButton(
                  onPressed: isGenerating ? null : generateVlog, 
                  child: const Text('Generate Vlog'),
                ),

                const SizedBox(height: 20),

                if (isGenerating)
                  const CircularProgressIndicator(),

                const SizedBox(height: 20),

                if (outputVideoPath != null) 
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Vlog Generated Success',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(outputVideoPath!),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
