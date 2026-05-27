import 'dart:io';
import 'dart:typed_data';
import 'package:image/image.dart' as img;

class FrameBuilder {

  // build frame
  Future<Uint8List> buildCompareFrame({
    required String userImagePath,
    required String? referenceImagePath,
    required String title,
  }) async {

    // load image
    final userBytes = await File(userImagePath).readAsBytes();
    final userImg = img.decodeImage(userBytes)!;

    img.Image? refImg;

    if (referenceImagePath != null) {
      final refBytes = await File(referenceImagePath).readAsBytes();
      refImg = img.decodeImage(refBytes);
    }

    // resize
    final resizedUser = img.copyResize(userImg, width: 500);
    final resizedRef = refImg != null
        ? img.copyResize(refImg, width: 500)
        : null;

    // build canvas
    final height = 500;
    final width = resizedRef != null ? 1000 : 500;

    // merge reference image and user photo
    final canvas = img.Image(width: width, height: height);
    if (resizedRef != null) {
      img.compositeImage(canvas, resizedRef, dstX: 0, dstY: 0);
      img.compositeImage(canvas, resizedUser, dstX: 500, dstY: 0);
    } else {
      img.compositeImage(canvas, resizedUser, dstX: 0, dstY: 0);
    }

    // add title
    img.drawString(
      canvas,
      title,
      font: img.arial14,
      x: 20,
      y: 20,
      );

    return Uint8List.fromList(img.encodeJpg(canvas));
  }
}