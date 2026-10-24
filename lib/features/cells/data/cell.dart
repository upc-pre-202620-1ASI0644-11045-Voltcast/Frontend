class Cell {
  const Cell({
    required this.id,
    required this.name,
    required this.isActive,
    this.barcodeValue,
  });

  final int id;

  /// Letter + number, uppercase: A1, B12.
  final String name;
  final bool isActive;

  /// `CELL-00001` once generated; null while pending.
  final String? barcodeValue;

  bool get hasBarcode => barcodeValue != null;

  // Entities are identified by id: a dropdown selection must still match its
  // item after the list is reloaded and every object is a new instance.
  @override
  bool operator ==(Object other) => other is Cell && other.id == id;

  @override
  int get hashCode => id.hashCode;

  factory Cell.fromJson(Map<String, dynamic> json) => Cell(
        id: json['id'] as int,
        name: json['name'] as String,
        isActive: json['is_active'] as bool,
        barcodeValue: json['barcode_value'] as String?,
      );
}

/// A1 < A2 < A10 < B1 (the backend names cells letter + number).
int compareCells(Cell a, Cell b) {
  final letters = a.name[0].compareTo(b.name[0]);
  if (letters != 0) return letters;
  final numA = int.tryParse(a.name.substring(1)) ?? 0;
  final numB = int.tryParse(b.name.substring(1)) ?? 0;
  return numA.compareTo(numB);
}
