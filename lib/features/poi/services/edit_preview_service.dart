import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Long edge of the editor's downscaled preview buffer. Most phone
/// screens are ~1080 px wide, so 1024 px stays visually crisp under
/// `BoxFit.contain` while keeping every per-pixel compute path well
/// under a second.
const int editingPreviewMaxDim = 1024;

/// Decode [sourceBytes], downscale to [editingPreviewMaxDim] on the
/// long edge when larger, and re-encode JPEG. When the source is
/// already small enough, returns the bytes unchanged so the editor
/// skips the round trip on already-tiny inputs.
///
/// Runs once when the editor mounts — every subsequent preview
/// compute (Match Color, Sharpness prepare, etc.) reads this output
/// instead of decoding the source again, so a 12 MP JPEG only pays
/// its ~300-500 ms decode cost a single time per editing session.
Future<Uint8List> downscaleForEditing(Uint8List sourceBytes) async {
  final image = img.decodeImage(sourceBytes);
  if (image == null) return sourceBytes;
  final long = math.max(image.width, image.height);
  if (long <= editingPreviewMaxDim) return sourceBytes;
  final scale = editingPreviewMaxDim / long;
  final downscaled = img.copyResize(
    image,
    width: (image.width * scale).round(),
    height: (image.height * scale).round(),
  );
  return Uint8List.fromList(img.encodeJpg(downscaled, quality: 90));
}
