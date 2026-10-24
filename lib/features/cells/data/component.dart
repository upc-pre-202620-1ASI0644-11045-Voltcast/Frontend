enum ComponentType {
  cathode('CATHODE', 'Cátodo', 'C'),
  anode('ANODE', 'Ánodo', 'A');

  const ComponentType(this.apiName, this.label, this.letter);

  final String apiName;
  final String label;
  final String letter;

  static ComponentType fromApi(String value) =>
      ComponentType.values.firstWhere((t) => t.apiName == value);
}

class Component {
  const Component({
    required this.id,
    required this.type,
    required this.serialCode,
    required this.isActive,
    this.cellId,
  });

  final int id;
  final ComponentType type;
  final String serialCode;
  final bool isActive;
  final int? cellId;

  /// Installed in a cell.
  bool get isInUse => isActive && cellId != null;

  /// Active and available to assign.
  bool get isFree => isActive && cellId == null;

  // Identified by id: dropdown selections survive a list reload.
  @override
  bool operator ==(Object other) => other is Component && other.id == id;

  @override
  int get hashCode => id.hashCode;

  factory Component.fromJson(Map<String, dynamic> json) => Component(
        id: json['id'] as int,
        type: ComponentType.fromApi(json['type'] as String),
        serialCode: json['serial_code'] as String,
        isActive: json['is_active'] as bool,
        cellId: json['cell_id'] as int?,
      );
}

int compareComponents(Component a, Component b) {
  final byType = a.type.index.compareTo(b.type.index);
  return byType != 0 ? byType : a.serialCode.compareTo(b.serialCode);
}
