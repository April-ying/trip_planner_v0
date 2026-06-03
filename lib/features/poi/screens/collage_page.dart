import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/providers/database_provider.dart';
import '../../anime/screens/cutout_editor_screen.dart';
import '../services/media_asset_service.dart';

/// 拼貼 / Compose — "edit page v2". Stacks cutout characters (and a translucent
/// reference overlay) onto the edited photo, each layer freely
/// dragged / scaled / rotated, then flattens to a `user_photo`.
///
/// Geometry is stored normalized over the base image (centerN 0..1, widthN as a
/// fraction of base width) so the on-screen preview and the full-res composite
/// use the same transform regardless of resolution.
class CollagePage extends ConsumerStatefulWidget {
  /// Downscaled edited photo for the canvas preview.
  final Uint8List basePreview;

  /// Resolves the full-resolution edited photo bytes for the final composite.
  final Future<Uint8List> Function() resolveFullResBase;

  final String referencePath;
  final String poiId;

  /// Return to the Adjust page (back arrow). Layers persist — the parent keeps
  /// this page alive in an IndexedStack.
  final VoidCallback onBack;

  const CollagePage({
    super.key,
    required this.basePreview,
    required this.resolveFullResBase,
    required this.referencePath,
    required this.poiId,
    required this.onBack,
  });

  @override
  ConsumerState<CollagePage> createState() => _CollagePageState();
}

class _CollageLayer {
  final ui.Image image;
  Offset centerN; // normalized center over the base image
  double widthN; // displayed width as a fraction of base width
  double rotation; // radians
  double opacity;
  _CollageLayer({
    required this.image,
    this.centerN = const Offset(0.5, 0.5),
    this.widthN = 0.5,
    this.rotation = 0,
    this.opacity = 1,
  });

  _CollageLayer copy() => _CollageLayer(
        image: image,
        centerN: centerN,
        widthN: widthN,
        rotation: rotation,
        opacity: opacity,
      );
}

class _CollagePageState extends ConsumerState<CollagePage> {
  final List<_CollageLayer> _layers = [];
  int? _selected;
  Size _baseSize = const Size(1, 1);

  bool _compare = false;
  bool _compareVertical = false; // false = side-by-side, true = stacked
  bool _busy = false;

  // Additive undo/redo: each committed op snapshots the layer list. Image refs
  // are shared across snapshots (and tracked in [_allImages] for disposal), so
  // delete is undoable without losing the bitmap.
  final List<List<_CollageLayer>> _history = [[]];
  int _histIndex = 0;
  final Set<ui.Image> _allImages = {};

  bool get _canUndo => _histIndex > 0;
  bool get _canRedo => _histIndex < _history.length - 1;

  // Gesture start snapshot for the selected layer.
  Offset _startCenterN = Offset.zero;
  double _startWidthN = 0;
  double _startRotation = 0;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    _readBaseSize();
  }

  @override
  void didUpdateWidget(CollagePage old) {
    super.didUpdateWidget(old);
    // Adjust edits changed the base while Compose stayed alive (IndexedStack) —
    // re-read its aspect so the preview + layer mapping stay correct.
    if (!identical(old.basePreview, widget.basePreview)) {
      _readBaseSize();
    }
  }

  @override
  void dispose() {
    for (final im in _allImages) {
      im.dispose();
    }
    super.dispose();
  }

  // ---- undo / redo --------------------------------------------------------

  /// Snapshot the current layer list onto the history (truncating any redo
  /// branch). Call after every committed op: add, delete, transform-end,
  /// opacity-end, adjust.
  void _pushHistory() {
    if (_histIndex < _history.length - 1) {
      _history.removeRange(_histIndex + 1, _history.length);
    }
    _history.add(_layers.map((l) => l.copy()).toList());
    _histIndex = _history.length - 1;
  }

  void _restore(int index) {
    _histIndex = index;
    _layers
      ..clear()
      ..addAll(_history[index].map((l) => l.copy()));
    if (_layers.isEmpty) {
      _selected = null;
    } else if (_selected != null) {
      _selected = _selected!.clamp(0, _layers.length - 1);
    }
  }

  void _undo() {
    if (_canUndo) setState(() => _restore(_histIndex - 1));
  }

  void _redo() {
    if (_canRedo) setState(() => _restore(_histIndex + 1));
  }

  Future<void> _readBaseSize() async {
    final codec = await ui.instantiateImageCodec(widget.basePreview);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() => _baseSize =
        Size(frame.image.width.toDouble(), frame.image.height.toDouble()));
    frame.image.dispose();
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  // ---- adding layers ------------------------------------------------------

  Future<void> _addCutout(CutoutEngine? _) async {
    if (_busy) return;
    final bytes = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(
        builder: (_) => CutoutEditorScreen(sourcePath: widget.referencePath),
      ),
    );
    if (!mounted || bytes == null) return;
    final image = await _decode(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _allImages.add(image);
      _layers.add(_CollageLayer(image: image, widthN: 0.5));
      _selected = _layers.length - 1;
      _pushHistory();
    });
  }

  Future<void> _addDirectOverlay() async {
    if (_busy) return;
    final bytes = await File(widget.referencePath).readAsBytes();
    final image = await _decode(bytes);
    if (!mounted) {
      image.dispose();
      return;
    }
    // Bake the translucent reference: full-cover, semi-transparent layer.
    setState(() {
      _allImages.add(image);
      _layers.add(_CollageLayer(image: image, widthN: 1.0, opacity: 0.4));
      _selected = _layers.length - 1;
      _pushHistory();
    });
  }

  void _deleteSelected() {
    final i = _selected;
    if (i == null) return;
    setState(() {
      _layers.removeAt(i); // image kept alive in history / _allImages
      _selected = _layers.isEmpty ? null : i.clamp(0, _layers.length - 1);
      _pushHistory();
    });
  }

  void _setOpacity(double v) {
    final i = _selected;
    if (i == null) return;
    setState(() => _layers[i].opacity = v);
  }

  // ---- composite + save ---------------------------------------------------

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final baseBytes = await widget.resolveFullResBase();
      final base = await _decode(baseBytes);
      final w = base.width, h = base.height;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder,
          Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
      canvas.drawImage(base, Offset.zero, Paint());
      for (final l in _layers) {
        final cx = l.centerN.dx * w;
        final cy = l.centerN.dy * h;
        final targetW = l.widthN * w;
        final s = targetW / l.image.width;
        canvas.save();
        canvas.translate(cx, cy);
        canvas.rotate(l.rotation);
        canvas.scale(s);
        canvas.drawImage(
          l.image,
          Offset(-l.image.width / 2, -l.image.height / 2),
          Paint()..color = Color.fromRGBO(0, 0, 0, l.opacity),
        );
        canvas.restore();
      }
      final picture = recorder.endRecording();
      final composed = await picture.toImage(w, h);
      base.dispose();
      picture.dispose();

      // With Compare on, save the side-by-side (composed | reference) in the
      // chosen orientation; otherwise just the composed image.
      ui.Image finalImg = composed;
      if (_compare) {
        final refImg =
            await _decode(await File(widget.referencePath).readAsBytes());
        finalImg = await _stitch(composed, refImg, _compareVertical);
        refImg.dispose();
        composed.dispose();
      }
      final png = await finalImg.toByteData(format: ui.ImageByteFormat.png);
      finalImg.dispose();
      if (png == null) throw 'compose failed';

      // Re-encode to JPEG (opaque result) so the saved file isn't a huge PNG.
      final jpg = img.encodeJpg(
        img.decodeImage(png.buffer.asUint8List())!,
        quality: 92,
      );
      final tmp = File(p.join(
        (await getTemporaryDirectory()).path,
        '${_compare ? 'compare' : 'collage'}_${_layers.length}.jpg',
      ));
      await tmp.writeAsBytes(jpg, flush: true);

      final ok = await persistMediaAsset(
        db: ref.read(databaseProvider),
        source: tmp,
        poiId: widget.poiId,
        type: _compare ? 'comparison_image' : 'user_photo',
      );
      if (await tmp.exists()) await tmp.delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok ? 'Collage saved.' : 'Save failed.')),
      );
      if (ok) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Stitch [a] and [b] together — side by side, or stacked when [vertical] —
  /// at a common height / width, preserving each image's aspect ratio.
  Future<ui.Image> _stitch(ui.Image a, ui.Image b, bool vertical) async {
    final aw = a.width.toDouble(), ah = a.height.toDouble();
    final bw = b.width.toDouble(), bh = b.height.toDouble();
    final double totalW, totalH;
    final Rect aDst, bDst;
    if (vertical) {
      final cw = aw > bw ? aw : bw;
      final aH = ah * cw / aw, bH = bh * cw / bw;
      totalW = cw;
      totalH = aH + bH;
      aDst = Rect.fromLTWH(0, 0, cw, aH);
      bDst = Rect.fromLTWH(0, aH, cw, bH);
    } else {
      final ch = ah > bh ? ah : bh;
      final aW = aw * ch / ah, bW = bw * ch / bh;
      totalW = aW + bW;
      totalH = ch;
      aDst = Rect.fromLTWH(0, 0, aW, ch);
      bDst = Rect.fromLTWH(aW, 0, bW, ch);
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalW, totalH));
    canvas.drawColor(Colors.white, BlendMode.src);
    final paint = Paint()..filterQuality = FilterQuality.high;
    canvas.drawImageRect(a, Rect.fromLTWH(0, 0, aw, ah), aDst, paint);
    canvas.drawImageRect(b, Rect.fromLTWH(0, 0, bw, bh), bDst, paint);
    final pic = recorder.endRecording();
    final out = await pic.toImage(totalW.round(), totalH.round());
    pic.dispose();
    return out;
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to Adjust',
          onPressed: _busy ? null : widget.onBack,
        ),
        title: const Text('Compose', style: TextStyle(fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: 'Undo',
            onPressed: _canUndo && !_busy ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.redo),
            tooltip: 'Redo',
            onPressed: _canRedo && !_busy ? _redo : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: TextButton(
              // Save is always available — with no layers it just saves the
              // adjusted photo (Compose is the single save point).
              onPressed: _busy ? null : _save,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                disabledForegroundColor: Colors.white38,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Save'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _buildCanvas()),
            if (_compare) _buildCompareBar(theme),
            _buildLayerStrip(theme),
            _buildToolRow(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildCanvas() {
    if (_compare) {
      // Each side re-fits to its own half (the composed view has its own
      // LayoutBuilder), so the current image shrinks to fit rather than getting
      // cropped to half. Side-by-side or stacked per _compareVertical.
      final composed = Expanded(child: _composedView());
      final reference = Expanded(
        child: Center(
          child: Image.file(File(widget.referencePath), fit: BoxFit.contain),
        ),
      );
      if (_compareVertical) {
        return Column(children: [
          composed,
          Container(height: 2, color: Colors.white24),
          reference,
        ]);
      }
      return Row(children: [
        composed,
        Container(width: 2, color: Colors.white24),
        reference,
      ]);
    }
    return _composedView();
  }

  Widget _composedView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cw = constraints.maxWidth, ch = constraints.maxHeight;
        final scale = (_baseSize.width <= 0 || _baseSize.height <= 0)
            ? 1.0
            : (cw / _baseSize.width).clamp(0.0, ch / _baseSize.height);
        final dispW = _baseSize.width * scale;
        final dispH = _baseSize.height * scale;
        final rect =
            Rect.fromLTWH((cw - dispW) / 2, (ch - dispH) / 2, dispW, dispH);

        return Stack(
          children: [
            Positioned.fromRect(
              rect: rect,
              child: Image.memory(widget.basePreview, fit: BoxFit.fill),
            ),
            for (var i = 0; i < _layers.length; i++) _layerWidget(i, rect),
            // One gesture surface drives the selected layer.
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _selected == null
                    ? null
                    : (d) {
                        final l = _layers[_selected!];
                        _startCenterN = l.centerN;
                        _startWidthN = l.widthN;
                        _startRotation = l.rotation;
                        _startFocal = d.focalPoint;
                      },
                onScaleUpdate: _selected == null
                    ? null
                    : (d) => setState(() {
                          final l = _layers[_selected!];
                          final dpx = d.focalPoint - _startFocal;
                          l.centerN = Offset(
                            (_startCenterN.dx + dpx.dx / dispW).clamp(0.0, 1.0),
                            (_startCenterN.dy + dpx.dy / dispH).clamp(0.0, 1.0),
                          );
                          l.widthN = (_startWidthN * d.scale).clamp(0.05, 3.0);
                          l.rotation = _startRotation + d.rotation;
                        }),
                onScaleEnd: _selected == null ? null : (_) => _pushHistory(),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _layerWidget(int i, Rect baseRect) {
    final l = _layers[i];
    final cx = baseRect.left + l.centerN.dx * baseRect.width;
    final cy = baseRect.top + l.centerN.dy * baseRect.height;
    final w = l.widthN * baseRect.width;
    final h = w * (l.image.height / l.image.width);
    return Positioned(
      left: cx - w / 2,
      top: cy - h / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Transform.rotate(
          angle: l.rotation,
          child: Opacity(
            opacity: l.opacity,
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: _selected == i
                    ? Border.all(color: Colors.amber, width: 2)
                    : null,
              ),
              child: RawImage(image: l.image, fit: BoxFit.fill),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLayerStrip(ThemeData theme) {
    if (_layers.isEmpty) return const SizedBox.shrink();
    final sel = _selected;
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _layers.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => setState(() => _selected = i),
                      child: Container(
                        width: 56,
                        decoration: BoxDecoration(
                          color: Colors.white10,
                          border: Border.all(
                            color: _selected == i
                                ? Colors.amber
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                        child: RawImage(image: _layers[i].image, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                  tooltip: 'Delete layer',
                  onPressed: sel == null ? null : _deleteSelected,
                ),
              ],
            ),
          ),
          if (sel != null)
            Row(
              children: [
                const Icon(Icons.opacity, size: 16, color: Colors.white54),
                Expanded(
                  child: Slider(
                    min: 0.1,
                    max: 1,
                    value: _layers[sel].opacity.clamp(0.1, 1),
                    onChanged: _setOpacity,
                    onChangeEnd: (_) => _pushHistory(),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildCompareBar(ThemeData theme) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('Compare layout',
              style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 12),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              foregroundColor: Colors.white70,
              selectedForegroundColor: Colors.white,
              selectedBackgroundColor: theme.colorScheme.primary,
              side: const BorderSide(color: Colors.white24),
              visualDensity: VisualDensity.compact,
            ),
            segments: const [
              ButtonSegment(
                  value: false,
                  icon: Icon(Icons.vertical_split),
                  tooltip: 'Side by side'),
              ButtonSegment(
                  value: true,
                  icon: Icon(Icons.horizontal_split),
                  tooltip: 'Stacked'),
            ],
            selected: {_compareVertical},
            onSelectionChanged: (s) =>
                setState(() => _compareVertical = s.first),
          ),
        ],
      ),
    );
  }

  Widget _buildToolRow(ThemeData theme) {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _tool(Icons.compare_arrows, 'Compare',
              selected: _compare,
              onTap: () => setState(() => _compare = !_compare)),
          _tool(Icons.auto_fix_high, 'Cutout', onTap: () => _addCutout(null)),
          _tool(Icons.layers, 'Overlay', onTap: _addDirectOverlay),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, String label,
      {bool selected = false, required VoidCallback onTap}) {
    final fg = selected ? Theme.of(context).colorScheme.primary : Colors.white70;
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: fg, size: 24),
            const SizedBox(height: 4),
            Text(label, style: TextStyle(color: fg, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}
