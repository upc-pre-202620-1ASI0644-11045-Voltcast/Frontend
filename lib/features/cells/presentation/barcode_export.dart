import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:share_plus/share_plus.dart';

/// Renders the widget under [boundaryKey] (a `RepaintBoundary`) to PNG bytes.
Future<Uint8List> capturePng(GlobalKey boundaryKey, {double pixelRatio = 3}) async {
  final boundary = boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw StateError('El código aún no está dibujado.');

  final image = await boundary.toImage(pixelRatio: pixelRatio);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('No se pudo generar la imagen.');
  return data.buffer.asUint8List();
}

/// Opens the system share sheet with the PNG so it can be saved to files,
/// printed or sent (on web it downloads the file).
Future<void> shareBarcodePng({required GlobalKey boundaryKey, required String fileName}) async {
  final bytes = await capturePng(boundaryKey);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'image/png')],
      fileNameOverrides: [fileName],
      subject: 'Código de barras',
    ),
  );
}
