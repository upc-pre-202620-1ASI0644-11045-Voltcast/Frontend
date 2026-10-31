import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:excel/excel.dart' show DoubleCellValue, Excel, TextCellValue;
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/format.dart';
import '../../../core/theme/app_theme.dart';
import '../data/forecast.dart';
import 'forecast_chart.dart';
import 'forecast_widgets.dart' show volts;

const pngMime = 'image/png';
const xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// Hands a finished file to the user. The default opens the system share sheet
/// (save to files, send…); on web it downloads it.
typedef ForecastFileSaver = Future<void> Function(
  String fileName,
  Uint8List bytes,
  String mimeType,
);

typedef ForecastPngBuilder = Future<Uint8List> Function({
  required String cellName,
  required List<ForecastItem> items,
});

Future<void> shareForecastFile(
  String fileName,
  Uint8List bytes,
  String mimeType,
) => SharePlus.instance.share(
  ShareParams(
    files: [XFile.fromData(bytes, mimeType: mimeType)],
    fileNameOverrides: [fileName],
    subject: 'Pronóstico de voltaje',
  ),
);

/// `pronostico_A1_2027-08-09_2028-02-04.png`
String forecastFileName(
  String cellName,
  List<ForecastItem> items,
  String ext,
) =>
    'pronostico_${cellName}_${apiDate(items.first.date)}_${apiDate(items.last.date)}.$ext';

/// The days of one cell as a workbook, numbers kept numeric so it can be
/// sorted and charted. A cell without limit leaves that column empty.
Uint8List forecastXlsx(List<ForecastItem> items) {
  final book = Excel.createExcel();
  const name = 'Pronóstico';
  book.rename(book.getDefaultSheet()!, name);
  final sheet = book[name];
  sheet.appendRow([
    for (final h in ['Fecha', 'Voltaje (V)', 'Límite (V)', 'Supera el límite'])
      TextCellValue(h),
  ]);
  for (final i in items) {
    sheet.appendRow([
      TextCellValue(apiDate(i.date)),
      DoubleCellValue(i.voltage),
      i.maxVoltage == null ? null : DoubleCellValue(i.maxVoltage!),
      TextCellValue(i.exceeds ? 'Sí' : 'No'),
    ]);
  }
  return Uint8List.fromList(book.encode()!);
}

/// The chart with its title and figures on a white sheet, as a PNG that reads
/// on its own once it leaves the app (a report, a chat).
Future<Uint8List> forecastPng({
  required String cellName,
  required List<ForecastItem> items,
  double pixelRatio = 2,
}) async {
  const width = 900.0, height = 560.0;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, width, height),
    Paint()..color = Colors.white,
  );

  void text(
    String value,
    Offset at, {
    double size = 16,
    FontWeight weight = FontWeight.w400,
    Color color = AppColors.ink,
  }) {
    TextPainter(
        text: TextSpan(
          text: value,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color),
        ),
        textDirection: TextDirection.ltr,
      )
      ..layout(maxWidth: width - at.dx - 32)
      ..paint(canvas, at);
  }

  final over = items.where((i) => i.exceeds).length;
  final highest = items.map((i) => i.voltage).reduce((a, b) => a > b ? a : b);
  final lowest = items.map((i) => i.voltage).reduce((a, b) => a < b ? a : b);
  final limit = items.map((i) => i.maxVoltage).whereType<double>().lastOrNull;

  text(
    'Celda $cellName',
    const Offset(32, 24),
    size: 28,
    weight: FontWeight.w800,
  );
  text(
    'Pronóstico de voltaje · ${formatShortDate(items.first.date)} – '
    '${formatShortDate(items.last.date)} · ${items.length} días',
    const Offset(32, 62),
    color: AppColors.muted,
  );

  canvas.save();
  canvas.translate(24, 100);
  ForecastChartPainter(
    items: items,
    limit: limit,
  ).paint(canvas, const Size(width - 48, 340));
  canvas.restore();

  text(
    'Voltaje máximo: ${volts(highest)}     Voltaje mínimo: ${volts(lowest)}',
    const Offset(32, 464),
    size: 18,
    weight: FontWeight.w700,
  );
  text(
    limit == null
        ? 'Sin límite configurado'
        : 'Límite ${volts(limit, 2)} · Días que superan el límite: $over',
    const Offset(32, 496),
    size: 18,
    weight: FontWeight.w700,
    color: over > 0 ? AppColors.error : AppColors.ink,
  );

  final image = await recorder.endRecording().toImage(
    (width * pixelRatio).round(),
    (height * pixelRatio).round(),
  );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  if (data == null) throw StateError('No se pudo generar la imagen.');
  return data.buffer.asUint8List();
}
