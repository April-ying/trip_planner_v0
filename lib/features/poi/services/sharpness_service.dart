import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../camera/services/band_runner.dart';

/// Sendable bundle for the sharpness adjust `compute()` helper.
class SharpnessArgs {
  /// JPEG-encoded source. The unsharp mask runs on whatever the editor
  /// was displaying when the user reached for this tool.
  final Uint8List sourceBytes;

  /// Unsharp-mask amount in [0, 1]. `0` returns the source unchanged;
  /// `1` adds the full detail layer back. Out-of-range values are
  /// clamped by the filter.
  final double amount;

  const SharpnessArgs({
    required this.sourceBytes,
    required this.amount,
  });
}

/// Unsharp-mask sharpening.
///
/// 1. Blur the image with a small-radius Gaussian (radius 2 — wide
///    enough to pick up edges without obliterating texture, narrow
///    enough that a 12 MP shot completes the blur in well under a
///    second on a phone).
/// 2. `result = original + amount * (original − blurred)`, clamped.
///
/// The blur lives in the main isolate (one pass over the buffer); the
/// per-pixel combine runs in parallel via [processBandsInParallel].
Future<Uint8List> applySharpness(SharpnessArgs args) async {
  final image = img.decodeImage(args.sourceBytes);
  if (image == null) return args.sourceBytes;
  final amount = args.amount.clamp(0.0, 1.0);
  if (amount == 0) return args.sourceBytes;

  // gaussianBlur returns a fresh Image; both buffers are the same
  // width × height × channel layout so we can index them with the
  // same offsets inside each band worker.
  final blurred = img.gaussianBlur(img.Image.from(image), radius: 2);
  final blurredData = blurred.toUint8List();
  final bytesPerRow = image.width * image.numChannels;

  return processBandsInParallel(
    captured: image,
    bandFn: (bytes, ch, w, yOff, bandH) {
      final byteStart = yOff * bytesPerRow;
      final byteEnd = byteStart + bandH * bytesPerRow;
      final blurredBand =
          Uint8List.sublistView(blurredData, byteStart, byteEnd);
      return _applySharpnessBand(bytes, blurredBand, ch, amount);
    },
  );
}

Uint8List _applySharpnessBand(
  Uint8List originalBand,
  Uint8List blurredBand,
  int channels,
  double amount,
) {
  final result = Uint8List.fromList(originalBand);
  final n = result.length;
  for (var i = 0; i < n; i += channels) {
    for (var c = 0; c < 3; c++) {
      final orig = originalBand[i + c];
      final blur = blurredBand[i + c];
      result[i + c] =
          (orig + amount * (orig - blur)).round().clamp(0, 255);
    }
  }
  return result;
}

// ---------------------------------------------------------------------------
//  Slider-preview path: downscale + blur are precomputed once when the user
//  enters sharpness mode (~1-2 s on a 12 MP shot, only happens at chip
//  tap), and every slider release after that just runs the per-pixel combine
//  on the cached ~1280 px downscaled buffers + a small JPEG encode (~300 ms
//  total instead of ~2-3 s). Save still re-runs the full-res `applySharpness`
//  above so on-disk quality isn't downscaled.
// ---------------------------------------------------------------------------

/// Sendable cache of the downscaled source + its Gaussian blur, used by
/// [applySharpnessQuick] for slider-release previews. Built once per
/// source via [prepareSharpness].
class PreparedSharpness {
  final Uint8List sourceRgba;
  final Uint8List blurredRgba;
  final int width;
  final int height;
  final int channels;

  const PreparedSharpness({
    required this.sourceRgba,
    required this.blurredRgba,
    required this.width,
    required this.height,
    required this.channels,
  });
}

class QuickSharpnessArgs {
  final PreparedSharpness prepared;
  final double amount;

  const QuickSharpnessArgs({
    required this.prepared,
    required this.amount,
  });
}

/// Decode the source, downscale to 1280 px on the long edge, and
/// Gaussian-blur the downscaled copy. The result is sendable and
/// stays cached on the editor for the lifetime of the sharpness tool —
/// subsequent slider releases reuse it via [applySharpnessQuick].
Future<PreparedSharpness> prepareSharpness(Uint8List sourceBytes) async {
  final image = img.decodeImage(sourceBytes);
  if (image == null) {
    throw StateError('prepareSharpness: decode failed');
  }

  const maxDim = 1280;
  final long = math.max(image.width, image.height);
  final img.Image downscaled;
  if (long <= maxDim) {
    downscaled = image;
  } else {
    final scale = maxDim / long;
    downscaled = img.copyResize(
      image,
      width: (image.width * scale).round(),
      height: (image.height * scale).round(),
    );
  }

  final blurred = img.gaussianBlur(img.Image.from(downscaled), radius: 2);

  return PreparedSharpness(
    sourceRgba: downscaled.toUint8List(),
    blurredRgba: blurred.toUint8List(),
    width: downscaled.width,
    height: downscaled.height,
    channels: downscaled.numChannels,
  );
}

/// Apply unsharp mask against the cached downscaled source + blur,
/// encode the result as JPEG. Used for slider-release previews — ~300
/// ms on a typical 1280 px buffer instead of the ~2-3 s full-res path.
Future<Uint8List> applySharpnessQuick(QuickSharpnessArgs args) async {
  final amount = args.amount.clamp(0.0, 1.0);
  final source = args.prepared.sourceRgba;
  final blurred = args.prepared.blurredRgba;
  final channels = args.prepared.channels;
  final n = source.length;

  final result = Uint8List.fromList(source);
  if (amount > 0) {
    for (var i = 0; i < n; i += channels) {
      for (var c = 0; c < 3; c++) {
        final orig = source[i + c];
        final blur = blurred[i + c];
        result[i + c] =
            (orig + amount * (orig - blur)).round().clamp(0, 255);
      }
    }
  }

  final image = img.Image.fromBytes(
    width: args.prepared.width,
    height: args.prepared.height,
    bytes: result.buffer,
    numChannels: channels,
  );
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}
