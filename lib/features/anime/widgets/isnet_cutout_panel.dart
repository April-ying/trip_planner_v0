import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../services/cutout_refine.dart';
import '../services/isnet_cutout_service.dart';
import 'cutout_checker.dart';

/// Reusable isnet-anime cutout panel: cuts a transparent-PNG subject out of
/// [source] and reports the current result via [onResult] (null until the first
/// cut). Engine-independent UI lives here so both the spike screen and the
/// collage cutout editor share it.
///
/// Tools — Box: crop the region before segmenting; Add/Erase: paint to force
/// regions opaque/transparent. Plus refine sliders (guided / gain / fill-holes
/// / feather). The panel owns its [IsnetCutoutService] and disposes it.
class IsnetCutoutPanel extends StatefulWidget {
  final File source;
  final ValueChanged<Uint8List?> onResult;
  const IsnetCutoutPanel({
    super.key,
    required this.source,
    required this.onResult,
  });

  @override
  State<IsnetCutoutPanel> createState() => _IsnetCutoutPanelState();
}

enum _Tool { box, add, erase }

/// A freeform brush stroke in SEG-IMAGE pixel coords.
class _Stroke {
  final List<Offset> pts;
  final double radius; // seg-image px
  final bool add;
  _Stroke(this.pts, this.radius, this.add);
}

class _IsnetCutoutPanelState extends State<IsnetCutoutPanel> {
  final _service = IsnetCutoutService();

  img.Image? _original; // decoded source, for display + cropping
  int _origW = 0;
  int _origH = 0;

  _Tool _tool = _Tool.box;

  Rect? _roi;
  Offset? _dragStart;

  img.Image? _segImage; // image the current mask was computed on (whole/crop)
  IsnetMask? _mask;

  double _brushSize = 36; // display px diameter
  final List<_Stroke> _strokes = [];
  Uint8List? _brush; // override at seg res: 0 none / 1 add / 2 erase

  bool _refine = true;
  bool _guided = true;
  double _gain = 1;
  bool _fillHoles = false;
  double _feather = 4;

  Uint8List? _resultPng;
  bool _processing = false;
  String? _status;

  // Model is fetched on first use (~176 MB), not bundled. Gate the cutout flow
  // on it being present; offer an explicit download so we never pull a large
  // file over cellular without consent.
  bool _modelReady = false;
  bool _checkingModel = true;
  bool _downloading = false;
  double? _downloadProgress; // 0..1, or null when total size is unknown
  String? _downloadError;

  @override
  void initState() {
    super.initState();
    _decode();
    _checkModel();
  }

  Future<void> _checkModel() async {
    final ready = await _service.store.isReady();
    if (!mounted) return;
    setState(() {
      _modelReady = ready;
      _checkingModel = false;
    });
  }

  Future<void> _downloadModel() async {
    setState(() {
      _downloading = true;
      _downloadError = null;
      _downloadProgress = null;
    });
    try {
      await _service.store.ensure(onProgress: (received, total) {
        if (!mounted || total == null || total <= 0) return;
        setState(() => _downloadProgress = received / total);
      });
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _modelReady = true;
        _status = 'Model ready. Optionally box the object, then "Cut out".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _downloadError =
            'Download failed: $e\nCheck your connection, or switch to the ML Kit engine (no download needed).';
      });
    }
  }

  @override
  void didUpdateWidget(IsnetCutoutPanel old) {
    super.didUpdateWidget(old);
    if (old.source.path != widget.source.path) _decode();
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _decode() async {
    final bytes = await widget.source.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (!mounted || decoded == null) return;
    setState(() {
      _original = decoded;
      _origW = decoded.width;
      _origH = decoded.height;
      _tool = _Tool.box;
      _roi = null;
      _mask = null;
      _segImage = null;
      _strokes.clear();
      _brush = null;
      _resultPng = null;
      _status = 'Optionally box the object, then "Cut out".';
    });
    widget.onResult(null);
  }

  img.Image _workImage() {
    final original = _original!;
    final roi = _roi;
    if (roi == null) return original;
    final left = roi.left.clamp(0, (_origW - 1).toDouble());
    final top = roi.top.clamp(0, (_origH - 1).toDouble());
    final width = roi.width.clamp(1, _origW - left).toDouble();
    final height = roi.height.clamp(1, _origH - top).toDouble();
    return img.copyCrop(original,
        x: left.round(),
        y: top.round(),
        width: width.round(),
        height: height.round());
  }

  Future<void> _cutout() async {
    if (_original == null) return;
    setState(() {
      _processing = true;
      _status = 'Running isnet-anime…';
    });
    try {
      final work = _workImage();
      final mask = await _service.segment(work);
      if (!mounted) return;
      _segImage = work;
      _mask = mask;
      _strokes.clear();
      _brush = null;
      await _recomposite(setProcessing: false);
      if (!mounted) return;
      setState(() {
        // Flip Box → Add so the canvas shows the cutout and brush-fix is ready.
        _tool = _Tool.add;
        _status = 'Done — refine, or Add/Erase to fix parts.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _processing = false;
        _status = 'Failed: $e';
      });
    }
  }

  Future<void> _recomposite({bool setProcessing = true}) async {
    final mask = _mask;
    final seg = _segImage;
    if (mask == null || seg == null) return;
    if (setProcessing) setState(() => _processing = true);
    final opt = _refine
        ? RefineOptions(
            guided: _guided,
            gain: _gain,
            fillHoles: _fillHoles,
            feather: _feather,
          )
        : const RefineOptions();
    final png = buildCutoutPng(seg, mask, opt, brush: _brush);
    if (!mounted) return;
    setState(() {
      _resultPng = png;
      _processing = false;
    });
    widget.onResult(png);
  }

  Uint8List? _rasterBrush() {
    final seg = _segImage;
    if (seg == null || _strokes.isEmpty) return null;
    final w = seg.width, h = seg.height;
    final out = Uint8List(w * h);
    void stamp(double cx, double cy, double r, int val) {
      final r2 = r * r;
      final x0 = (cx - r).floor().clamp(0, w - 1);
      final x1 = (cx + r).ceil().clamp(0, w - 1);
      final y0 = (cy - r).floor().clamp(0, h - 1);
      final y1 = (cy + r).ceil().clamp(0, h - 1);
      for (var y = y0; y <= y1; y++) {
        for (var x = x0; x <= x1; x++) {
          final dx = x - cx, dy = y - cy;
          if (dx * dx + dy * dy <= r2) out[y * w + x] = val;
        }
      }
    }

    for (final s in _strokes) {
      final val = s.add ? 1 : 2;
      for (var i = 0; i < s.pts.length; i++) {
        final pt = s.pts[i];
        stamp(pt.dx, pt.dy, s.radius, val);
        if (i > 0) {
          final q = s.pts[i - 1];
          final dist = (pt - q).distance;
          final steps = (dist / math.max(1.0, s.radius * 0.5)).ceil();
          for (var k = 1; k < steps; k++) {
            final t = k / steps;
            stamp(q.dx + (pt.dx - q.dx) * t, q.dy + (pt.dy - q.dy) * t,
                s.radius, val);
          }
        }
      }
    }
    return out;
  }

  void _onClear() {
    if (_tool == _Tool.box) {
      setState(() => _roi = null);
    } else {
      setState(() {
        _strokes.clear();
        _brush = null;
      });
      _recomposite();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_original == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final canvasH = MediaQuery.sizeOf(context).height * 0.34;
    return Column(
      children: [
        SizedBox(
          height: canvasH,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Center(child: _buildCanvas(canvasH - 24)),
          ),
        ),
        _toolBar(),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_status != null)
                Text(_status!, style: Theme.of(context).textTheme.bodySmall),
              if (_mask != null) ...[
                const SizedBox(height: 8),
                _refineControls(),
              ],
              if (_processing) ...[
                const SizedBox(height: 16),
                const Center(child: CircularProgressIndicator()),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCanvas(double maxH) {
    final showResult =
        _tool != _Tool.box && _resultPng != null && _segImage != null;
    return showResult ? _buildResultCanvas(maxH) : _buildInputCanvas(maxH);
  }

  Widget _buildInputCanvas(double maxH) {
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
        final boxing = _tool == _Tool.box && !_processing;
        return SizedBox(
          width: dispW,
          height: dispH,
          child: GestureDetector(
            onPanStart: boxing
                ? (d) => setState(() {
                      _dragStart = toOrig(d.localPosition);
                      _roi = Rect.fromPoints(_dragStart!, _dragStart!);
                    })
                : null,
            onPanUpdate: boxing
                ? (d) => setState(() {
                      if (_dragStart != null) {
                        _roi = Rect.fromPoints(
                            _dragStart!, toOrig(d.localPosition));
                      }
                    })
                : null,
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

  Widget _buildResultCanvas(double maxH) {
    final seg = _segImage!;
    final segW = seg.width, segH = seg.height;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = math.min(constraints.maxWidth / segW, maxH / segH);
        final dispW = segW * scale;
        final dispH = segH * scale;
        Offset toSeg(Offset local) => Offset(
              (local.dx / scale).clamp(0, segW.toDouble()),
              (local.dy / scale).clamp(0, segH.toDouble()),
            );
        return SizedBox(
          width: dispW,
          height: dispH,
          child: GestureDetector(
            onPanStart: _processing
                ? null
                : (d) => setState(() {
                      final r = (_brushSize / 2) / scale;
                      _strokes.add(_Stroke(
                          [toSeg(d.localPosition)], r, _tool == _Tool.add));
                    }),
            onPanUpdate: _processing
                ? null
                : (d) => setState(() {
                      if (_strokes.isNotEmpty) {
                        _strokes.last.pts.add(toSeg(d.localPosition));
                      }
                    }),
            onPanEnd: _processing
                ? null
                : (_) {
                    _brush = _rasterBrush();
                    _recomposite();
                  },
            child: CutoutChecker(
              child: Stack(
                children: [
                  Image.memory(_resultPng!,
                      width: dispW, height: dispH, fit: BoxFit.fill),
                  Positioned.fill(
                    child: CustomPaint(painter: _StrokePainter(_strokes, scale)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// The action area shown while the Box tool is active: either the model
  /// download prompt/progress, or the normal "Cut out" button once ready.
  Widget _boxActions() {
    if (_checkingModel) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }
    if (!_modelReady) {
      if (_downloading) {
        final pct = _downloadProgress;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pct == null
                    ? 'Downloading AI model…'
                    : 'Downloading AI model… ${(pct * 100).round()}%',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: pct),
            ],
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _downloadModel,
              icon: const Icon(Icons.download),
              label: const Text('Download AI model (~176 MB)'),
            ),
          ),
          Text(
            'One-time download for the isnet engine. Or use the ML Kit engine — no download needed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_downloadError != null) ...[
            const SizedBox(height: 6),
            Text(_downloadError!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      );
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: FilledButton.icon(
        onPressed: _processing ? null : _cutout,
        icon: const Icon(Icons.content_cut),
        label: const Text('Cut out'),
      ),
    );
  }

  Widget _toolBar() {
    final hasResult = _resultPng != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              SegmentedButton<_Tool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: _Tool.box,
                      icon: Icon(Icons.crop_free),
                      tooltip: 'Box'),
                  ButtonSegment(
                      value: _Tool.add,
                      icon: Icon(Icons.add),
                      tooltip: 'Add'),
                  ButtonSegment(
                      value: _Tool.erase,
                      icon: Icon(Icons.remove),
                      tooltip: 'Erase'),
                ],
                selected: {_tool},
                onSelectionChanged: _processing
                    ? null
                    : (s) {
                        final t = s.first;
                        if (t != _Tool.box && !hasResult) return;
                        setState(() => _tool = t);
                      },
              ),
              const Spacer(),
              TextButton(
                  onPressed: _processing ? null : _onClear,
                  child: Text(_tool == _Tool.box ? 'Clear box' : 'Clear brush')),
            ],
          ),
          if (_tool == _Tool.box)
            _boxActions()
          else
            Row(
              children: [
                const Icon(Icons.brush, size: 18),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 80,
                    value: _brushSize,
                    label: _brushSize.round().toString(),
                    onChanged: _processing
                        ? null
                        : (v) => setState(() => _brushSize = v),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _refineControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('修毛邊 (edge refine)'),
          value: _refine,
          onChanged: _processing
              ? null
              : (v) {
                  setState(() => _refine = v);
                  _recomposite();
                },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Guided filter (edge-snap)'),
          value: _guided,
          onChanged: (!_refine || _processing)
              ? null
              : (v) {
                  setState(() => _guided = v);
                  _recomposite();
                },
        ),
        _slider('Keep more', _gain, 1, 3, _gain.toStringAsFixed(1),
            (v) => setState(() => _gain = v),
            divisions: 20),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fill holes'),
          value: _fillHoles,
          onChanged: (!_refine || _processing)
              ? null
              : (v) {
                  setState(() => _fillHoles = v);
                  _recomposite();
                },
        ),
        _slider('Feather', _feather, 0, 12, _feather.round().toString(),
            (v) => setState(() => _feather = v)),
      ],
    );
  }

  Widget _slider(String label, double value, double min, double max,
      String display, ValueChanged<double> onChanged,
      {int? divisions}) {
    final enabled = _refine && !_processing;
    return Row(
      children: [
        SizedBox(width: 120, child: Text('$label  $display')),
        Expanded(
          child: Slider(
            min: min,
            max: max,
            divisions: divisions ?? (max - min).round(),
            value: value,
            label: display,
            onChanged: enabled ? onChanged : null,
            onChangeEnd: enabled ? (_) => _recomposite() : null,
          ),
        ),
      ],
    );
  }
}

/// Translucent overlay of the add (green) / erase (red) strokes.
class _StrokePainter extends CustomPainter {
  final List<_Stroke> strokes;
  final double scale;
  _StrokePainter(this.strokes, this.scale);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      if (s.pts.isEmpty) continue;
      final paint = Paint()
        ..color = (s.add ? Colors.greenAccent : Colors.redAccent)
            .withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.radius * 2 * scale;
      final path = Path()
        ..moveTo(s.pts.first.dx * scale, s.pts.first.dy * scale);
      for (final pt in s.pts.skip(1)) {
        path.lineTo(pt.dx * scale, pt.dy * scale);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter old) => true;
}
