class AlertRule {
  const AlertRule({
    required this.id,
    required this.maxVoltage,
    required this.isActive,
    this.cellId,
  });

  final int id;

  /// Null is the general limit; a cell's own rule replaces it for that cell.
  final int? cellId;
  final double maxVoltage;
  final bool isActive;

  factory AlertRule.fromJson(Map<String, dynamic> json) => AlertRule(
    id: json['id'] as int,
    cellId: json['cell_id'] as int?,
    maxVoltage: (json['max_voltage'] as num).toDouble(),
    isActive: json['is_active'] as bool,
  );
}
