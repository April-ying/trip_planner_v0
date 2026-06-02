import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'isnet_cutout_service.dart';

/// SPIKE — edge-refinement ("修毛邊") for the isnet soft mask, plus compositing
/// to a transparent PNG. All ops run on the 1024² mask (cheap) before the mask
/// is upscaled as the alpha channel, so the sliders re-composite fast.
///
/// - guided: edge-aware guided filter — snaps the alpha border to the real
///   image edge, killing jaggies (uses the input luma as guide).
/// - erode: morphological shrink — trims the bright background halo/fringe.
/// - feather: box-blur (×3 ≈ gaussian) — softens the remaining edge.
class RefineOptions {
  final bool guided;

  /// Soft-mask multiplier, 1 = off. >1 recovers faint, low-confidence
  /// foreground the model almost dropped ("keep more of the character").
  final double gain;

  /// Fill background pockets fully enclosed by foreground (interior holes).
  final bool fillHoles;

  final double feather; // blur radius, px @1024
  const RefineOptions({
    this.guided = false,
    this.gain = 1,
    this.fillHoles = false,
    this.feather = 0,
  });
}

/// Refines [m] per [opt] and composites onto [original] → transparent PNG bytes.
///
/// [brush] is an optional per-pixel add/erase override at [original] resolution
/// (length w*h: 0 = none, 1 = force opaque, 2 = force transparent) — the
/// add-back brush, applied after the soft mask so the user can recover dropped
/// parts or cut extras with guaranteed effect.
Uint8List buildCutoutPng(img.Image original, IsnetMask m, RefineOptions opt,
    {Uint8List? brush}) {
  final res = m.res;
  var mask = Float32List.fromList(m.mask);

  // Order: guided (edge-snap) → gain (recover faint fg) → fill holes →
  // feather (soften).
  if (opt.guided) {
    mask = _guidedFilter(m.guideLuma, mask, res, res, radius: 8, eps: 1e-4);
  }
  if (opt.gain != 1.0) {
    for (var i = 0; i < mask.length; i++) {
      mask[i] = (mask[i] * opt.gain).clamp(0.0, 1.0);
    }
  }
  if (opt.fillHoles) {
    mask = _fillHoles(mask, res, res);
  }
  if (opt.feather > 0) {
    mask = _boxBlur(mask, res, res, opt.feather.round(), passes: 3);
  }

  // Composite over raw byte buffers — getPixel/setPixelRgba per pixel was the
  // other main-thread freeze (Pixel-object alloc per call over a full-res image).
  final w = original.width;
  final h = original.height;
  // Same letterbox transform segment() used, recomputed to map mask → original.
  final scale = math.min(res / w, res / h);
  final padX = (res - w * scale) / 2;
  final padY = (res - h * scale) / 2;
  final origRgb = original.getBytes(order: img.ChannelOrder.rgb);
  final out = Uint8List(w * h * 4);
  var o = 0;
  for (var y = 0; y < h; y++) {
    final my = padY + y * scale;
    for (var x = 0; x < w; x++) {
      var a =
          _sampleBilinear(mask, res, res, padX + x * scale, my).clamp(0.0, 1.0);
      if (brush != null) {
        final b = brush[y * w + x];
        if (b == 1) {
          a = 1.0;
        } else if (b == 2) {
          a = 0.0;
        }
      }
      final si = (y * w + x) * 3;
      out[o++] = origRgb[si];
      out[o++] = origRgb[si + 1];
      out[o++] = origRgb[si + 2];
      out[o++] = (a * 255).round();
    }
  }
  final outImg = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: out.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodePng(outImg);
}

/// Feather (and optionally erode) the alpha of an existing RGBA cutout PNG.
/// Used to soften hard-edged cutouts like ML Kit subject bitmaps — erode first
/// to pull the edge into solid foreground (kills the halo / dark fringe), then
/// feather to soften. Returns the input unchanged if both are zero.
Uint8List featherCutoutPng(Uint8List rgbaPng, {int erode = 0, double feather = 0}) {
  if (erode <= 0 && feather <= 0) return rgbaPng;
  final im = img.decodeImage(rgbaPng);
  if (im == null) return rgbaPng;
  final w = im.width;
  final h = im.height;
  final rgba = im.getBytes(order: img.ChannelOrder.rgba);
  var a = Float32List(w * h);
  for (var i = 0; i < w * h; i++) {
    a[i] = rgba[i * 4 + 3] / 255.0;
  }
  if (erode > 0) a = _erode(a, w, h, erode);
  if (feather > 0) a = _boxBlur(a, w, h, feather.round(), passes: 3);
  for (var i = 0; i < w * h; i++) {
    rgba[i * 4 + 3] = (a[i].clamp(0.0, 1.0) * 255).round();
  }
  final out = img.Image.fromBytes(
    width: w,
    height: h,
    bytes: rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodePng(out);
}

// ---- mask ops (row-major Float32, 0..1) ---------------------------------

/// Separable box blur, [passes] applications ≈ a gaussian of the same radius.
Float32List _boxBlur(Float32List src, int w, int h, int r, {int passes = 1}) {
  if (r <= 0) return src;
  var cur = src;
  for (var p = 0; p < passes; p++) {
    cur = _boxPass(cur, w, h, r);
  }
  return cur;
}

Float32List _boxPass(Float32List src, int w, int h, int r) {
  final win = 2 * r + 1;
  final tmp = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    var sum = 0.0;
    for (var k = -r; k <= r; k++) {
      sum += src[row + k.clamp(0, w - 1)];
    }
    for (var x = 0; x < w; x++) {
      tmp[row + x] = sum / win;
      sum += src[row + (x + r + 1).clamp(0, w - 1)] -
          src[row + (x - r).clamp(0, w - 1)];
    }
  }
  final dst = Float32List(w * h);
  for (var x = 0; x < w; x++) {
    var sum = 0.0;
    for (var k = -r; k <= r; k++) {
      sum += tmp[k.clamp(0, h - 1) * w + x];
    }
    for (var y = 0; y < h; y++) {
      dst[y * w + x] = sum / win;
      sum += tmp[(y + r + 1).clamp(0, h - 1) * w + x] -
          tmp[(y - r).clamp(0, h - 1) * w + x];
    }
  }
  return dst;
}

/// Morphological erosion (separable square min-filter, radius [e]).
Float32List _erode(Float32List src, int w, int h, int e) {
  final tmp = Float32List(w * h);
  for (var y = 0; y < h; y++) {
    final row = y * w;
    for (var x = 0; x < w; x++) {
      var mn = 1.0;
      for (var k = -e; k <= e; k++) {
        final v = src[row + (x + k).clamp(0, w - 1)];
        if (v < mn) mn = v;
      }
      tmp[row + x] = mn;
    }
  }
  final dst = Float32List(w * h);
  for (var x = 0; x < w; x++) {
    for (var y = 0; y < h; y++) {
      var mn = 1.0;
      for (var k = -e; k <= e; k++) {
        final v = tmp[(y + k).clamp(0, h - 1) * w + x];
        if (v < mn) mn = v;
      }
      dst[y * w + x] = mn;
    }
  }
  return dst;
}

/// Fill background pockets fully enclosed by foreground: flood-fill background
/// inward from the borders, then promote any unreached below-threshold pixel
/// (an interior hole) to solid foreground.
Float32List _fillHoles(Float32List src, int w, int h, {double thr = 0.5}) {
  final n = w * h;
  final reached = Uint8List(n); // 1 = background reachable from the border
  final stack = <int>[];
  void seed(int i) {
    if (src[i] < thr && reached[i] == 0) {
      reached[i] = 1;
      stack.add(i);
    }
  }

  for (var x = 0; x < w; x++) {
    seed(x);
    seed((h - 1) * w + x);
  }
  for (var y = 0; y < h; y++) {
    seed(y * w);
    seed(y * w + w - 1);
  }
  while (stack.isNotEmpty) {
    final i = stack.removeLast();
    final x = i % w, y = i ~/ w;
    if (x > 0) seed(i - 1);
    if (x < w - 1) seed(i + 1);
    if (y > 0) seed(i - w);
    if (y < h - 1) seed(i + w);
  }
  final dst = Float32List.fromList(src);
  for (var i = 0; i < n; i++) {
    if (src[i] < thr && reached[i] == 0) dst[i] = 1.0; // enclosed hole
  }
  return dst;
}

/// He et al. guided filter — edge-aware mask refinement using luma [I] as guide.
Float32List _guidedFilter(Float32List I, Float32List p, int w, int h,
    {int radius = 8, double eps = 1e-4}) {
  final n = w * h;
  final ip = Float32List(n);
  final ii = Float32List(n);
  for (var i = 0; i < n; i++) {
    ip[i] = I[i] * p[i];
    ii[i] = I[i] * I[i];
  }
  final meanI = _boxPass(I, w, h, radius);
  final meanP = _boxPass(p, w, h, radius);
  final meanIp = _boxPass(ip, w, h, radius);
  final meanII = _boxPass(ii, w, h, radius);
  final a = Float32List(n);
  final b = Float32List(n);
  for (var i = 0; i < n; i++) {
    final varI = meanII[i] - meanI[i] * meanI[i];
    final covIp = meanIp[i] - meanI[i] * meanP[i];
    a[i] = covIp / (varI + eps);
    b[i] = meanP[i] - a[i] * meanI[i];
  }
  final meanA = _boxPass(a, w, h, radius);
  final meanB = _boxPass(b, w, h, radius);
  final q = Float32List(n);
  for (var i = 0; i < n; i++) {
    q[i] = (meanA[i] * I[i] + meanB[i]).clamp(0.0, 1.0);
  }
  return q;
}

double _sampleBilinear(Float32List m, int w, int h, double fx, double fy) {
  if (fx < 0) fx = 0;
  if (fy < 0) fy = 0;
  final x0 = fx.floor().clamp(0, w - 1);
  final y0 = fy.floor().clamp(0, h - 1);
  final x1 = (x0 + 1).clamp(0, w - 1);
  final y1 = (y0 + 1).clamp(0, h - 1);
  final dx = fx - x0;
  final dy = fy - y0;
  final top = m[y0 * w + x0] + (m[y0 * w + x1] - m[y0 * w + x0]) * dx;
  final bot = m[y1 * w + x0] + (m[y1 * w + x1] - m[y1 * w + x0]) * dx;
  return top + (bot - top) * dy;
}
