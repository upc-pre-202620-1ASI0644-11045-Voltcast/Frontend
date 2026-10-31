import '../../../core/format.dart';
import 'forecast.dart';

/// One cell on the day: what the model forecast against what was measured.
class EvaluationItem {
  const EvaluationItem({
    required this.cellId,
    required this.cellName,
    required this.real,
    required this.predicted,
    required this.errorV,
    required this.errorPct,
  });

  final int cellId;
  final String cellName;
  final double real, predicted;

  /// Difference in volts and in %, as the API computes them.
  final double errorV, errorPct;

  factory EvaluationItem.fromJson(Map<String, dynamic> json) => EvaluationItem(
    cellId: json['cell_id'] as int,
    cellName: json['cell_name'] as String,
    real: (json['real'] as num).toDouble(),
    predicted: (json['predicted'] as num).toDouble(),
    errorV: (json['error_v'] as num).toDouble(),
    errorPct: (json['error_pct'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'cell_id': cellId,
    'cell_name': cellName,
    'real': real,
    'predicted': predicted,
    'error_v': errorV,
    'error_pct': errorPct,
  };
}

/// `GET /forecasts/evaluation`: the worst (or best) cells of one validation day.
class EvaluationResult {
  const EvaluationResult({
    required this.items,
    this.model,
    this.retraining = false,
    this.message,
    this.availableFrom,
    this.availableTo,
    this.date,
    this.totalCells = 0,
    this.meanErrorPct,
    this.savedAt,
  });

  final ModelInfo? model;
  final bool retraining;
  final String? message;
  final DateTime? availableFrom, availableTo;

  /// The day the items belong to.
  final DateTime? date;
  final int totalCells;

  /// Mean error of the whole day, not only of [items].
  final double? meanErrorPct;
  final List<EvaluationItem> items;

  /// Set when the data comes from the device (offline), with the day it was saved.
  final DateTime? savedAt;

  bool get isOffline => savedAt != null;

  factory EvaluationResult.fromJson(Map<String, dynamic> json) =>
      EvaluationResult(
        model: ModelInfo.maybe(json['model']),
        retraining: json['retraining'] as bool? ?? false,
        message: json['message'] as String?,
        availableFrom: json['available_from'] is String
            ? parseApiDate(json['available_from'] as String)
            : null,
        availableTo: json['available_to'] is String
            ? parseApiDate(json['available_to'] as String)
            : null,
        date: json['date'] is String
            ? parseApiDate(json['date'] as String)
            : null,
        totalCells: (json['total_cells'] as num? ?? 0).toInt(),
        meanErrorPct: (json['mean_error_pct'] as num?)?.toDouble(),
        items: [
          for (final e in json['items'] as List? ?? const [])
            EvaluationItem.fromJson(e as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
    'model': model?.toJson(),
    'retraining': retraining,
    'message': message,
    'available_from': availableFrom == null ? null : apiDate(availableFrom!),
    'available_to': availableTo == null ? null : apiDate(availableTo!),
    'date': date == null ? null : apiDate(date!),
    'total_cells': totalCells,
    'mean_error_pct': meanErrorPct,
    'items': [for (final i in items) i.toJson()],
  };

  /// The same answer reduced to [limit] rows in [order] (read from a longer
  /// one), marked as coming from the device since [saved].
  EvaluationResult top(int limit, String order, DateTime saved) {
    final sorted = [...items]
      ..sort(
        (a, b) => order == 'best'
            ? a.errorPct.compareTo(b.errorPct)
            : b.errorPct.compareTo(a.errorPct),
      );
    return EvaluationResult(
      items: sorted.take(limit).toList(),
      model: model,
      retraining: retraining,
      message: message,
      availableFrom: availableFrom,
      availableTo: availableTo,
      date: date,
      totalCells: totalCells,
      meanErrorPct: meanErrorPct,
      savedAt: saved,
    );
  }
}
