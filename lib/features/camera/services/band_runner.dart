import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Per-pixel filter work is split across this many worker isolates. 4 is a
/// pragmatic default — most Android phones expose 4–8 physical cores and
/// the gain tails off quickly past that because the per-filter decode +
/// LUT-build phases stay sequential.
const int _parallelBands = 4;

/// Per-band processing function. Receives the raw RGB(A) pixel bytes for one
/// horizontal slice of the captured image and must return the modified bytes
/// for that slice (same length, same layout, in place is fine — the helper
/// reads what comes back, not the original buffer).
///
/// `yOffset` + `bandHeight` tell the function where its slice sits inside
/// the full image. Only the patch-based filters actually need them; the
/// global histogram filters can ignore both via `_`.
typedef BandFn = Uint8List Function(
  Uint8List bandBytes,
  int channels,
  int width,
  int yOffset,
  int bandHeight,
);

/// Split [captured]'s decoded pixel buffer into [_parallelBands] horizontal
/// bands, run [bandFn] on each band in its own isolate via `Isolate.run`,
/// stitch the modified bands back into a contiguous buffer, wrap them in
/// a new `img.Image`, and re-encode as JPEG (quality 90).
///
/// Decode and LUT/stats prep stay sequential in the calling isolate — they
/// are cheap relative to the per-pixel apply phase, which is where the cost
/// lives on a 12 MP shot. `Isolate.run` works inside a `compute()` worker
/// because it's just a wrapper around `Isolate.spawn` and doesn't need the
/// root isolate token.
Future<Uint8List> processBandsInParallel({
  required img.Image captured,
  required BandFn bandFn,
}) async {
  final width = captured.width;
  final height = captured.height;
  final channels = captured.numChannels;
  final data = captured.toUint8List();
  final bytesPerRow = width * channels;

  // Ceil so the last band picks up any remainder rows.
  final bandRowCount = (height / _parallelBands).ceil();
  final futures = <Future<Uint8List>>[];

  for (var b = 0; b < _parallelBands; b++) {
    final y0 = b * bandRowCount;
    if (y0 >= height) break;
    final y1 = math.min((b + 1) * bandRowCount, height);
    final actualHeight = y1 - y0;
    // `sublist` returns a fresh Uint8List, so each isolate gets its own
    // copy of its band to mutate without aliasing the source buffer.
    final bandBytes = data.sublist(y0 * bytesPerRow, y1 * bytesPerRow);

    futures.add(
      Isolate.run(
        () => bandFn(bandBytes, channels, width, y0, actualHeight),
      ),
    );
  }

  final results = await Future.wait(futures);

  // Stitch the per-band results into a single contiguous buffer.
  final totalBytes = results.fold<int>(0, (sum, r) => sum + r.length);
  final stitched = Uint8List(totalBytes);
  var offset = 0;
  for (final r in results) {
    stitched.setRange(offset, offset + r.length, r);
    offset += r.length;
  }

  final newImage = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: stitched.buffer,
    numChannels: channels,
  );
  return Uint8List.fromList(img.encodeJpg(newImage, quality: 90));
}
