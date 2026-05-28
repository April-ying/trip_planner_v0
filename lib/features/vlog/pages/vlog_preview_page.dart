import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:trip_planner/core/providers/database_provider.dart';
import 'package:trip_planner/features/roi/providers/roi_provider.dart';
import 'package:gal/gal.dart';

import '../data/vlog_repository.dart';
import '../services/frame_builder.dart';
import '../services/ffmpeg_service.dart';

class VlogPreviewPage extends ConsumerStatefulWidget {

    const VlogPreviewPage({super.key});

    @override
    ConsumerState<VlogPreviewPage> createState() => _VlogPreviewPageState();
}

class _VlogPreviewPageState extends ConsumerState<VlogPreviewPage> {

  String? selectedRoiId;

  bool isGenerating = false;
  
  String? outputVideoPath;

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

      // build frame
      final frameBuilder = FrameBuilder();

      List<String> framePaths = [];

      for (int i = 0; i < frameSource.length; i++) {
        final source = frameSource[i];

        final bytes = await frameBuilder.buildCompareFrame(
          userImagePath: source.userImagePath,
          referenceImagePath: source.referenceImagePath,
          title: source.poiName,
        );

        // store as temp frame
        final tempFile = File(
          '${Directory.systemTemp.path}/frame_$i.jpg'
        );

        await tempFile.writeAsBytes(bytes);

        framePaths.add(tempFile.path);
        if (i == frameSource.length - 1) framePaths.add(tempFile.path); // add last frame one more time

        // test
        debugPrint(tempFile.path);
      }

      // generate mp4
      final ffmpeg = FFmpegService();

      final videoPath = await ffmpeg.createVideoFromImages(
        imagePaths: framePaths,
        secondsPerImage: 4,
      );

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
