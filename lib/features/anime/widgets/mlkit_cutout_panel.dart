import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_mlkit_subject_segmentation/google_mlkit_subject_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/cutout_refine.dart';
import 'cutout_checker.dart';

/// Reusable ML Kit (Google) subject-cutout panel: optionally box-crop [source],
/// auto-detect subjects, tap one, feather its edge. Reports the current cutout
/// PNG via [onResult]. Mirrors [IsnetCutoutPanel]'s contract so the collage
/// cutout editor can swap engines.
class MlkitCutoutPanel extends StatefulWidget {
  final File source;
  final ValueChanged<Uint8List?> onResult;
  const MlkitCutoutPanel({
    super.key,
    required this.source,
    required this.onResult,
  });

  @override
  State<MlkitCutoutPanel> createState() => _MlkitCutoutPanelState();
}

class _MlkitCutoutPanelState extends State<MlkitCutoutPanel> {
  int _origW = 0;
  int _origH = 0;

  Rect? _roi;
  Offset? _dragStart;

  List<Subject> _results = const [];
  int? _selected;

  double _erode = 0;
  double _feather = 4;
  Uint8List? _refinedPng;

  bool _processing = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _readDims();
  }

  @override
  void didUpdateWidget(MlkitCutoutPanel old) {
    super.didUpdateWidget(old);
    if (old.source.path != widget.source.path) _readDims();
  }

  Future<void> _readDims() async {
    final bytes = await widget.source.readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width, h = frame.image.height;
    frame.image.dispose();
    if (!mounted) return;
    setState(() {
      _origW = w;
      _origH = h;
      _roi = null;
      _results = const [];
      _selected = null;
      _refinedPng = null;
      _status = 'Optionally box the object, then "Cut out".';
    });
    widget.onResult(null);
  }

  Future<File> _cropToBox() async {
    final roi = _roi;
    if (roi == null) return widget.source;
    final left = roi.left.clamp(0, (_origW - 1).toDouble());
    final top = roi.top.clamp(0, (_origH - 1).toDouble());
    final width = roi.width.clamp(1, _origW - left).toDouble();
    final height = roi.height.clamp(1, _origH - top).toDouble();
    final decoded = img.decodeImage(await widget.source.readAsBytes());
    if (decoded == null) return widget.source;
    final crop = img.copyCrop(decoded,
        x: left.round(),
        y: top.round(),
        width: width.round(),
        height: height.round());
    final dir = await getTemporaryDirectory();
    final path = p.join(dir.path, 'mlkit_roi_crop.png');
    await File(path).writeAsBytes(img.encodePng(crop), flush: true);
    return File(path);
  }

  Future<void> _segment() async {
    setState(() {
      _processing = true;
      _results = const [];
      _selected = null;
      _refinedPng = null;
      _status = _roi != null ? 'Segmenting selection…' : 'Segmenting whole…';
    });
    widget.onResult(null);
    final segmenter = SubjectSegmenter(
      options: SubjectSegmenterOptions(
        enableForegroundBitmap: false,
        enableForegroundConfidenceMask: false,
        enableMultipleSubjects: SubjectResultOptions(
          enableConfidenceMask: false,
          enableSubjectBitmap: true,
        ),
      ),
    );
    try {
      final file = await _cropToBox();
      final result =
          await segmenter.processImage(InputImage.fromFilePath(file.path));
      if (!mounted) return;
      setState(() {
        _results = result.subjects;
        _processing = false;
        _status = result.subjects.isEmpty
            ? 'No subjects detected — tighten the box.'
            : '${result.subjects.length} subject'
                '${result.subjects.length == 1 ? '' : 's'} — tap one below.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _status = 'Failed (model may be downloading — retry): $e';
      });
    } finally {
      await segmenter.close();
    }
  }

  void _applyRefine() {
    final i = _selected;
    final bmp = i == null ? null : _results[i].bitmap;
    _refinedPng = bmp == null
        ? null
        : featherCutoutPng(bmp, erode: _erode.round(), feather: _feather);
    widget.onResult(_refinedPng);
  }

  @override
  Widget build(BuildContext context) {
    final canvasH = MediaQuery.sizeOf(context).height * 0.34;
    return Column(
      children: [
        SizedBox(
          height: canvasH,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(child: _buildImage(canvasH - 24)),
          ),
        ),
        _buildControls(),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_processing)
                const Center(child: CircularProgressIndicator())
              else if (_status != null)
                Text(_status!, style: Theme.of(context).textTheme.bodyMedium),
              if (_results.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildResults(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildImage(double maxH) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = (_origW == 0 || _origH == 0)
            ? 1.0
            : math.min(constraints.maxWidth / _origW, maxH / _origH);
        final dispW = _origW * scale;
        final dispH = _origH * scale;
        Offset toOrig(Offset local) => Offset(
              (local.dx / scale).clamp(0, _origW.toDouble()),
              (local.dy / scale).clamp(0, _origH.toDouble()),
            );
        return SizedBox(
          width: dispW,
          height: dispH,
          child: GestureDetector(
            onPanStart: _processing
                ? null
                : (d) => setState(() {
                      _dragStart = toOrig(d.localPosition);
                      _roi = Rect.fromPoints(_dragStart!, _dragStart!);
                    }),
            onPanUpdate: _processing
                ? null
                : (d) => setState(() {
                      if (_dragStart != null) {
                        _roi = Rect.fromPoints(
                            _dragStart!, toOrig(d.localPosition));
                      }
                    }),
            child: Stack(
              children: [
                Image.file(widget.source,
                    width: dispW, height: dispH, fit: BoxFit.fill),
                if (_roi != null)
                  Positioned.fromRect(
                    rect: Rect.fromLTRB(_roi!.left * scale, _roi!.top * scale,
                        _roi!.right * scale, _roi!.bottom * scale),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.amber, width: 2),
                        color: Colors.amber.withValues(alpha: 0.15),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          FilledButton.icon(
            onPressed: _processing ? null : _segment,
            icon: const Icon(Icons.content_cut),
            label: const Text('Cut out'),
          ),
          const Spacer(),
          TextButton(
            onPressed: _processing ? null : () => setState(() => _roi = null),
            child: const Text('Clear box'),
          ),
        ],
      ),
    );
  }

  Widget _buildResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _results.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final bmp = _results[i].bitmap;
              return GestureDetector(
                onTap: () => setState(() {
                  _selected = i;
                  _applyRefine();
                }),
                child: Container(
                  width: 96,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    border: Border.all(
                      color: _selected == i ? Colors.amber : Colors.transparent,
                      width: 3,
                    ),
                  ),
                  child: bmp == null
                      ? const Center(child: Text('—'))
                      : Image.memory(bmp, fit: BoxFit.contain),
                ),
              );
            },
          ),
        ),
        if (_selected != null) ...[
          const SizedBox(height: 12),
          CutoutChecker(
            child: Image.memory(
                _refinedPng ?? _results[_selected!].bitmap ?? Uint8List(0)),
          ),
          const SizedBox(height: 8),
          _refineSlider('Erode', _erode, 0, 6, (v) => _erode = v),
          _refineSlider('Feather (羽化)', _feather, 0, 12, (v) => _feather = v),
        ],
      ],
    );
  }

  Widget _refineSlider(
      String label, double value, double min, double max, ValueChanged<double> set) {
    return Row(
      children: [
        SizedBox(width: 120, child: Text('$label  ${value.round()}')),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: (max - min).round(),
            value: value,
            label: value.round().toString(),
            onChanged: _processing ? null : (v) => setState(() => set(v)),
            onChangeEnd: _processing ? null : (_) => setState(_applyRefine),
          ),
        ),
      ],
    );
  }
}
