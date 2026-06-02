import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'band_runner.dart';

/// Sendable bundle of input bytes for the colour-match `compute()` helpers.
/// Holds primitives only so closures inside instance methods can't leak the
/// surrounding widget state across the isolate boundary.
class MatchArgs {
  final Uint8List capturedBytes;
  final Uint8List referenceBytes;

  const MatchArgs({
    required this.capturedBytes,
    required this.referenceBytes,
  });
}

/// Sendable bundle for the lerp helper. JPEG-encoded buffers in, JPEG out.
class LerpArgs {
  final Uint8List jpegA;
  final Uint8List jpegB;
  final double strength;

  const LerpArgs({
    required this.jpegA,
    required this.jpegB,
    required this.strength,
  });
}

/// Reinhard, Adhikhmin, Gooch & Shirley (2001) "Color Transfer between
/// Images" applied as the "Match Color" filter.
///
/// Both images are converted to LAB. Mean + stddev for L, a, b are
/// computed on 256 px thumbnails. For every captured pixel:
///
///     new_L = (L - cap.meanL) * (ref.stdL / cap.stdL) + ref.meanL
///     new_a = (a - cap.meanA) * (ref.stdA / cap.stdA) + ref.meanA
///     new_b = (b - cap.meanB) * (ref.stdB / cap.stdB) + ref.meanB
///
/// Closed form, no iteration — the result is the "full strength" match.
/// The editor lerps this output against the original capture with a
/// strength slider, so this function does not itself need to know about
/// strength: 100 % match is the only thing it produces.
///
/// Each per-channel scale is clamped to [0.5, 2.0] so a monochrome or
/// very flat reference can't blow up the captured image's chroma.
Future<Uint8List> reinhardMatch(MatchArgs args) async {
  final captured = img.decodeImage(args.capturedBytes);
  final reference = img.decodeImage(args.referenceBytes);
  if (captured == null || reference == null) return args.capturedBytes;

  final capStats = _labStats(_thumb(captured));
  final refStats = _labStats(_thumb(reference));

  return processBandsInParallel(
    captured: captured,
    bandFn: (bytes, ch, _, _, _) =>
        _applyReinhardBand(bytes, ch, capStats, refStats),
  );
}

Uint8List _applyReinhardBand(
  Uint8List bandBytes,
  int channels,
  _LabStats cap,
  _LabStats ref,
) {
  final result = Uint8List.fromList(bandBytes);
  final n = result.length;

  final scaleL = (ref.stdL / cap.stdL).clamp(0.5, 2.0);
  final scaleA = (ref.stdA / cap.stdA).clamp(0.5, 2.0);
  final scaleB = (ref.stdB / cap.stdB).clamp(0.5, 2.0);

  for (var i = 0; i < n; i += channels) {
    final lab = _rgbToLab(result[i], result[i + 1], result[i + 2]);
    final newL = (lab.l - cap.meanL) * scaleL + ref.meanL;
    final newA = (lab.a - cap.meanA) * scaleA + ref.meanA;
    final newB = (lab.b - cap.meanB) * scaleB + ref.meanB;
    final rgb = _labToRgb(newL, newA, newB);
    result[i] = rgb.r.round().clamp(0, 255);
    result[i + 1] = rgb.g.round().clamp(0, 255);
    result[i + 2] = rgb.b.round().clamp(0, 255);
  }
  return result;
}

/// Per-byte linear blend between two same-sized JPEG buffers, re-encoded
/// as JPEG. Used by the editor's Save flow to flatten the Match Color
/// strength slider (which renders as a Flutter Stack at preview time)
/// into a single byte stream for `savePhoto`.
///
/// Both buffers must decode to the same width × height × channel layout
/// — the function is only called from inside the editor after Reinhard
/// produced its match against this exact captured image, so that holds.
Future<Uint8List> lerpJpegs(LerpArgs args) async {
  final a = img.decodeImage(args.jpegA);
  final b = img.decodeImage(args.jpegB);
  if (a == null || b == null) return args.jpegA;

  final aData = a.toUint8List();
  final bData = b.toUint8List();
  if (aData.length != bData.length) return args.jpegA;

  final t = args.strength.clamp(0.0, 1.0);
  final invT = 1 - t;
  final out = Uint8List(aData.length);
  for (var i = 0; i < aData.length; i++) {
    out[i] = (aData[i] * invT + bData[i] * t).round().clamp(0, 255);
  }

  final newImage = img.Image.fromBytes(
    width: a.width,
    height: a.height,
    bytes: out.buffer,
    numChannels: a.numChannels,
  );
  return Uint8List.fromList(img.encodeJpg(newImage, quality: 90));
}

// ---------------------------------------------------------------------------
//  LAB stats + conversion — duplicated from color_match_service to keep
//  this file self-contained. Reach for a shared helper if a third LAB
//  consumer shows up.
// ---------------------------------------------------------------------------

img.Image _thumb(img.Image src) {
  const longEdge = 256;
  if (src.width <= longEdge && src.height <= longEdge) return src;
  return src.width >= src.height
      ? img.copyResize(src, width: longEdge)
      : img.copyResize(src, height: longEdge);
}

class _LabStats {
  final double meanL, meanA, meanB;
  final double stdL, stdA, stdB;
  const _LabStats({
    required this.meanL,
    required this.meanA,
    required this.meanB,
    required this.stdL,
    required this.stdA,
    required this.stdB,
  });
}

_LabStats _labStats(img.Image src) {
  var sumL = 0.0, sumA = 0.0, sumB = 0.0;
  var sqL = 0.0, sqA = 0.0, sqB = 0.0;
  var count = 0;

  for (final px in src) {
    final lab = _rgbToLab(px.r, px.g, px.b);
    sumL += lab.l;
    sumA += lab.a;
    sumB += lab.b;
    sqL += lab.l * lab.l;
    sqA += lab.a * lab.a;
    sqB += lab.b * lab.b;
    count++;
  }

  if (count == 0) {
    return const _LabStats(
      meanL: 0, meanA: 0, meanB: 0,
      stdL: 1, stdA: 1, stdB: 1,
    );
  }
  final meanL = sumL / count;
  final meanA = sumA / count;
  final meanB = sumB / count;
  final varL = math.max(0.0, sqL / count - meanL * meanL);
  final varA = math.max(0.0, sqA / count - meanA * meanA);
  final varB = math.max(0.0, sqB / count - meanB * meanB);
  return _LabStats(
    meanL: meanL,
    meanA: meanA,
    meanB: meanB,
    stdL: math.max(1e-6, math.sqrt(varL)),
    stdA: math.max(1e-6, math.sqrt(varA)),
    stdB: math.max(1e-6, math.sqrt(varB)),
  );
}

class _LabPixel {
  final double l, a, b;
  const _LabPixel(this.l, this.a, this.b);
}

class _RgbPixel {
  final double r, g, b;
  const _RgbPixel(this.r, this.g, this.b);
}

double _srgbToLinear(double v8) {
  final v = v8 / 255.0;
  return v <= 0.04045
      ? v / 12.92
      : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
}

double _linearToSrgb(double v) {
  final r = v <= 0.0031308
      ? 12.92 * v
      : 1.055 * math.pow(v, 1.0 / 2.4).toDouble() - 0.055;
  return r * 255.0;
}

double _labF(double t) {
  return t > 0.008856
      ? math.pow(t, 1.0 / 3.0).toDouble()
      : (7.787 * t) + (16.0 / 116.0);
}

double _labFInv(double t) {
  return t > 0.206893 ? t * t * t : (t - 16.0 / 116.0) / 7.787;
}

_LabPixel _rgbToLab(num r8, num g8, num b8) {
  final lr = _srgbToLinear(r8.toDouble());
  final lg = _srgbToLinear(g8.toDouble());
  final lb = _srgbToLinear(b8.toDouble());

  final x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375;
  final y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750;
  final z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041;

  const xn = 0.95047, yn = 1.0, zn = 1.08883;
  final fx = _labF(x / xn);
  final fy = _labF(y / yn);
  final fz = _labF(z / zn);

  return _LabPixel(
    116.0 * fy - 16.0,
    500.0 * (fx - fy),
    200.0 * (fy - fz),
  );
}

_RgbPixel _labToRgb(double l, double a, double b) {
  final fy = (l + 16.0) / 116.0;
  final fx = a / 500.0 + fy;
  final fz = fy - b / 200.0;

  const xn = 0.95047, yn = 1.0, zn = 1.08883;
  final x = xn * _labFInv(fx);
  final y = yn * _labFInv(fy);
  final z = zn * _labFInv(fz);

  final lr = x * 3.2404542 + y * -1.5371385 + z * -0.4985314;
  final lg = x * -0.9692660 + y * 1.8760108 + z * 0.0415560;
  final lb = x * 0.0556434 + y * -0.2040259 + z * 1.0572252;

  return _RgbPixel(
    _linearToSrgb(lr.clamp(0.0, 1.0)),
    _linearToSrgb(lg.clamp(0.0, 1.0)),
    _linearToSrgb(lb.clamp(0.0, 1.0)),
  );
}
