import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:image/image.dart' as img;

class FrameBuilder {

  // image resize
  img.Image resizeToFit(img.Image src, int boxW, int boxH) {

    final scale = math.min(
      boxW / src.width,
      boxH / src.height,
    );

    final newW = (src.width * scale).round();
    final newH = (src.height * scale).round();

    return img.copyResize(src, width: newW, height: newH);
  }

  // panel size
  ({int width, int height}) _panelSizeForImage(
    img.Image image, {
    required int padding,
  }) {
    return (
      width: image.width + padding * 2, 
      height: image.height + padding * 2,
    );
  }

  // draw border
  void _drawBorder(
    img.Image src, {
    required int x, 
    required int y, 
    required int w, 
    required int h,
    required img.Color color,
    int thickness = 4,
  }) {
    img.drawRect(
      src,
      x1: x,
      y1: y,
      x2: x + w,
      y2: y + h,
      color: color,
      thickness: thickness,
    );
  }

  // image panel
  void _placeImageInPanel(
    img.Image canvas, {
    required img.Image src, 
    required int panelX,
    required int panelY,
    required int panelW,
    required int panelH,
    required img.Color paddingColor,
  }) {
    img.fillRect(
      canvas,
      x1: panelX,
      y1: panelY,
      x2: panelX + panelW,
      y2: panelY + panelH,
      color: paddingColor,
    );

    final imageX = panelX + (panelW - src.width) ~/ 2;
    final imageY = panelY + (panelH - src.height) ~/ 2;

    img.compositeImage(
      canvas,
      src,
      dstX: imageX,
      dstY: imageY,
    );
  }

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

    // parameter
    const frameW = 1080;
    const frameH = 620;

    const mainX = 60;
    const mainY = 120;
    const mainW = 960;
    const mainH = 420;

    const titleW = 480;
    const titleH = 70;
    const titleY = 50;

    const maxInnerW = 420;
    const maxInnerH = 340;
    const padding = 18;
    const panelGap = 48;

    // color
    final canvasColor = img.ColorRgb8(156, 103, 58); // wood
    final panelColor = img.ColorRgb8(255, 255, 255); // white
    final borderColor = img.ColorRgb8(0, 0, 0);      // black
    final titleColor = img.ColorRgb8(0, 0, 0);       // black

    // construct canvas
    final canvas = img.Image(
      width: frameW, 
      height: frameH,
      );
    img.fill(canvas, color: canvasColor);

    // resize image
    final resizedUser = resizeToFit(userImg, maxInnerW, maxInnerH);
    final resizedRef = refImg == null
        ? null
        : resizeToFit(refImg, maxInnerW, maxInnerH);
    final hasRef = resizedRef != null;

    // calculate panel size
    final userPanelSize = _panelSizeForImage(resizedUser, padding: padding);
    final refPanelSize = resizedRef == null
        ? (width: 0, height: 0)
        : _panelSizeForImage(resizedRef, padding: padding);

    final totalPanelW = hasRef
        ? refPanelSize.width + panelGap + userPanelSize.width
        : userPanelSize.width;
    final leftPanelX = hasRef
        ? (frameW - totalPanelW) ~/ 2
        : 0;
    final rightPanelX = hasRef
        ? leftPanelX + refPanelSize.width + panelGap
        : (frameW - totalPanelW) ~/ 2;

    final panelCenterY = mainY + mainH ~/ 2;
    final leftPanelY = hasRef
        ? panelCenterY - refPanelSize.height ~/ 2
        : 0;
    final rightPanelY = panelCenterY - userPanelSize.height ~/ 2;
    
    // main window
    _drawBorder(
      canvas,
      x: mainX,
      y: mainY,
      w: mainW,
      h: mainH,
      color: borderColor,
      thickness: 5,
    );

    // Left (reference)
    if (resizedRef != null) {
      _placeImageInPanel(
        canvas, 
        src: resizedRef, 
        panelX: leftPanelX, 
        panelY: leftPanelY, 
        panelW: refPanelSize.width, 
        panelH: refPanelSize.height,
        paddingColor: panelColor
      );

      _drawBorder(
        canvas, 
        x: leftPanelX, 
        y: leftPanelY, 
        w: refPanelSize.width, 
        h: refPanelSize.height, 
        color: borderColor,
      );
    }

    // Right (user photo)
  _placeImageInPanel(
      canvas, 
      src: resizedUser, 
      panelX: rightPanelX, 
      panelY: rightPanelY, 
      panelW: userPanelSize.width, 
      panelH: userPanelSize.height,
      paddingColor: panelColor
    );

    _drawBorder(
      canvas, 
      x: rightPanelX, 
      y: rightPanelY, 
      w: userPanelSize.width, 
      h: userPanelSize.height, 
      color: borderColor,
    );

    // add title
    final titleX = (frameW - titleW) ~/ 2;
    img.fillRect(
      canvas,
      x1: titleX,
      y1: titleY,
      x2: titleX + titleW,
      y2: titleY + titleH,
      color: panelColor,
    );

    _drawBorder(
      canvas, 
      x: titleX, 
      y: titleY, 
      w: titleW, 
      h: titleH, 
      color: borderColor,
    );

    img.drawString(
      canvas,
      title,
      font: img.arial48,
      y: titleY + 10,
      color: titleColor,
      );

    return Uint8List.fromList(img.encodeJpg(canvas));
  }
}