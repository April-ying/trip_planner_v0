import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../../camera/services/band_runner.dart';

/// Sendable bundle for the brightness adjust `compute()` helper.
class BrightnessArgs {
  /// JPEG-encoded source — whatever the editor was displaying at the
  /// moment the user reached for this tool. The result chains on top.
  final Uint8List sourceBytes;

  /// Multiplier offset: `0` is identity, `+0.5` brightens (each RGB
  /// channel × 1.5, clamped), `-0.5` darkens (× 0.5). The editor's
  /// slider feeds values in [-0.5, +0.5]; out-of-range values are
  /// clamped by the filter.
  final double brightness;

  const BrightnessArgs({
    required this.sourceBytes,
    required this.brightness,
  });
}

/// Multiplicative brightness adjust over the whole image. Scaling
/// each channel by `(1 + brightness)` preserves hue exactly (the
/// channel ratio doesn't change) and keeps blacks at black —
/// additive shifts wash shadows out, which the gallery pickers
/// usually don't want.
Future<Uint8List> applyBrightness(BrightnessArgs args) async {
  final image = img.decodeImage(args.sourceBytes);
  if (image == null) return args.sourceBytes;
  final scale = 1 + args.brightness.clamp(-0.5, 0.5);
  return processBandsInParallel(
    captured: image,
    bandFn: (bytes, ch, _, _, _) => _applyBrightnessBand(bytes, ch, scale),
  );
}

Uint8List _applyBrightnessBand(
  Uint8List bandBytes,
  int channels,
  double scale,
) {
  final result = Uint8List.fromList(bandBytes);
  final n = result.length;
  for (var i = 0; i < n; i += channels) {
    result[i] = (result[i] * scale).round().clamp(0, 255);
    result[i + 1] = (result[i + 1] * scale).round().clamp(0, 255);
    result[i + 2] = (result[i + 2] * scale).round().clamp(0, 255);
  }
  return result;
}
