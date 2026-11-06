import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:share_plus/share_plus.dart';

import '../data/evaluation.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

/// The comparison as a workbook: one row per cell, the table's columns, with
/// numbers kept numeric so the sheet can be sorted and calculated on.
Uint8List evaluationXlsx(List<EvaluationItem> rows) {
  final book = Excel.createExcel();
  const name = 'Comparación';
  book.rename(book.getDefaultSheet()!, name);
  final sheet = book[name];
  sheet.appendRow([
    for (final h in [
      'Celda',
      'V. Real',
      'Pronóstico',
      'Diferencia (V)',
      'Error (%)',
    ])
      TextCellValue(h),
  ]);
  for (final i in rows) {
    sheet.appendRow([
      TextCellValue(i.cellName),
      DoubleCellValue(i.real),
      DoubleCellValue(i.predicted),
      DoubleCellValue(i.errorV),
      DoubleCellValue(i.errorPct),
    ]);
  }
  return Uint8List.fromList(book.encode()!);
}

/// Builds the file and opens the system share sheet so it can be saved to
/// files or sent (on web it downloads it).
Future<void> shareEvaluationXlsx(
  String fileName,
  List<EvaluationItem> rows,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(evaluationXlsx(rows), mimeType: _xlsxMime)],
      fileNameOverrides: [fileName],
      subject: 'Comparación de pronóstico',
    ),
  );
}
