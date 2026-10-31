import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

typedef PickedFile = ({String name, Uint8List bytes});

/// Opens the system file selector, which only offers `.xlsx` and `.xlsm`.
/// Returns null when the user cancels.
typedef ExcelPicker = Future<PickedFile?> Function();

Future<PickedFile?> pickExcelFile() async {
  final files = await FilePickerPlatform.instance.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx', 'xlsm'],
  );
  if (files.isEmpty) return null;
  return (name: files.first.name, bytes: await files.first.readAsBytes());
}
