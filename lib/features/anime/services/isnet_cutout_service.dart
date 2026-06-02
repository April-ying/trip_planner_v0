import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'isnet_model_store.dart';

/// SPIKE — isnet-anime (rembg) on-device cutout via ONNX Runtime.
///
/// This is the *non-Google* path: an anime-tuned ISNet that auto-segments the
/// foreground character/object (no prompt). It returns a single soft mask. We
/// keep inference (slow, ~1–2 s) separate from edge refinement (fast) so the
/// "修毛邊" sliders can re-composite without re-running the model.
///
/// Model: isnet-anime.onnx (~176 MB), fetched on first use by [IsnetModelStore]
/// and cached in app storage — never bundled or committed. Input NCHW
/// [1,3,1024,1024], RGB, value = x/255-0.5. Output [1,1,1024,1024] soft logits
/// → min-max normalized to a 0..1 mask.
class IsnetMask {
  /// Soft foreground mask, [res]×[res], row-major, 0..1.
  final Float32List mask;

  /// Luma of the 1024² resized input, row-major, 0..1 — guide for guided filter.
  final Float32List guideLuma;

  /// Mask/guide resolution (model input size, 1024).
  final int res;

  const IsnetMask({
    required this.mask,
    required this.guideLuma,
    required this.res,
  });
}

class IsnetCutoutService {
  IsnetCutoutService({IsnetModelStore? store})
      : store = store ?? IsnetModelStore();

  /// Resolves/downloads/caches the model file. Exposed so UI can check
  /// readiness and drive the download with progress before the first cut.
  final IsnetModelStore store;

  static const int inputRes = 1024;

  static bool _envReady = false;
  OrtSession? _session;

  Future<void> _ensureSession() async {
    if (_session != null) return;
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    // ensure() returns immediately if the model is already cached; the panel
    // downloads it (with progress) before getting here, so this is normally
    // just a disk lookup.
    final modelFile = await store.ensure();
    _session = OrtSession.fromFile(modelFile, OrtSessionOptions());
  }

  /// Runs isnet on [original], returning a soft mask + guide at 1024² so the
  /// caller can refine + composite at will. Throws if the model fails to load.
  Future<IsnetMask> segment(img.Image original) async {
    await _ensureSession();
    final session = _session!;

    // Letterbox the original into the square model input — a plain squash
    // distorts the character (thin parts like limbs/hair fall below the model's
    // resolution and get dropped). Preserve aspect, pad with black; the same
    // letterbox transform is recomputed in buildCutoutPng to map the mask back.
    final scale =
        math.min(inputRes / original.width, inputRes / original.height);
    final newW = math.max(1, (original.width * scale).round());
    final newH = math.max(1, (original.height * scale).round());
    final padX = ((inputRes - newW) / 2).floor();
    final padY = ((inputRes - newH) / 2).floor();
    final fit = img.copyResize(
      original,
      width: newW,
      height: newH,
      interpolation: img.Interpolation.cubic,
    );
    final canvas = img.Image(width: inputRes, height: inputRes, numChannels: 3);
    img.fill(canvas, color: img.ColorRgb8(0, 0, 0));
    img.compositeImage(canvas, fit, dstX: padX, dstY: padY);

    // Build NCHW float tensor (R,G,B planes), x/255 - 0.5. Capture luma too.
    // Read the raw RGB byte buffer once — getPixel() per-pixel is an order of
    // magnitude slower (allocates a Pixel view each call) and was freezing the
    // UI. This loop is now sub-100ms for 1024².
    const plane = inputRes * inputRes;
    final rgb = canvas.getBytes(order: img.ChannelOrder.rgb);
    final input = Float32List(3 * plane);
    final guideLuma = Float32List(plane);
    for (var i = 0; i < plane; i++) {
      final r = rgb[i * 3] / 255.0;
      final g = rgb[i * 3 + 1] / 255.0;
      final b = rgb[i * 3 + 2] / 255.0;
      input[i] = r - 0.5; // R plane
      input[plane + i] = g - 0.5; // G plane
      input[2 * plane + i] = b - 0.5; // B plane
      guideLuma[i] = 0.299 * r + 0.587 * g + 0.114 * b;
    }

    final inputName = session.inputNames.first;
    final tensor = OrtValueTensor.createTensorWithDataList(
      input,
      [1, 3, inputRes, inputRes],
    );
    final runOptions = OrtRunOptions();
    List<OrtValue?>? outputs;
    try {
      // runAsync runs the native inference on the plugin's own isolate, so the
      // multi-second forward pass no longer blocks the UI thread.
      outputs = await session.runAsync(runOptions, {inputName: tensor});
      final mask = _readMask(outputs!.first!.value, plane);
      return IsnetMask(mask: mask, guideLuma: guideLuma, res: inputRes);
    } finally {
      tensor.release();
      runOptions.release();
      if (outputs != null) {
        for (final o in outputs) {
          o?.release();
        }
      }
    }
  }

  /// Descends leading size-1 dims of the ONNX output to a [res]×[res] grid,
  /// then min-max normalizes to 0..1.
  Float32List _readMask(dynamic value, int plane) {
    dynamic v = value;
    while (v is List && v.length == 1 && v.first is List && (v.first as List).first is List) {
      v = v.first;
    }
    final rows = v as List; // [res][res]
    final out = Float32List(plane);
    var mn = double.infinity, mx = -double.infinity;
    var k = 0;
    for (final row in rows) {
      for (final cell in row as List) {
        final d = (cell as num).toDouble();
        out[k++] = d;
        if (d < mn) mn = d;
        if (d > mx) mx = d;
      }
    }
    final span = (mx - mn).abs() < 1e-9 ? 1.0 : (mx - mn);
    for (var j = 0; j < out.length; j++) {
      out[j] = (out[j] - mn) / span;
    }
    return out;
  }

  void dispose() {
    _session?.release();
    _session = null;
  }
}
