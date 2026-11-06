import '../../../core/format.dart';
import 'forecast.dart';

/// One validation day: the mean error of every cell that day.
class SeriesPoint {
  const SeriesPoint({
    required this.date,
    required this.meanErrorPct,
    required this.totalCells,
  });

  final DateTime date;
  final double meanErrorPct;
  final int totalCells;

  factory SeriesPoint.fromJson(Map<String, dynamic> json) => SeriesPoint(
    date: parseApiDate(json['date'] as String),
    meanErrorPct: (json['mean_error_pct'] as num).toDouble(),
    totalCells: (json['total_cells'] as num? ?? 0).toInt(),
  );

  Map<String, dynamic> toJson() => {
    'date': apiDate(date),
    'mean_error_pct': meanErrorPct,
    'total_cells': totalCells,
  };
}

/// `GET /forecasts/evaluation/series`: one point per validation day. It does
/// not depend on the day the table shows, so it is asked once per screen.
class EvaluationSeries {
  const EvaluationSeries({
    required this.items,
    this.model,
    this.retraining = false,
    this.message,
    this.availableFrom,
    this.availableTo,
    this.savedAt,
  });

  final List<SeriesPoint> items;
  final ModelInfo? model;
  final bool retraining;

  /// What to show when there is no model (and so no points).
  final String? message;
  final DateTime? availableFrom, availableTo;

  /// Set when the data comes from the device (offline), with the day it was saved.
  final DateTime? savedAt;

  /// Days the series covers, for texts like "los últimos 60 días".
  int? get days => availableFrom == null || availableTo == null
      ? null
      : availableTo!.difference(availableFrom!).inDays + 1;

  factory EvaluationSeries.fromJson(Map<String, dynamic> json) =>
      EvaluationSeries(
        model: ModelInfo.maybe(json['model']),
        retraining: json['retraining'] as bool? ?? false,
        message: json['message'] as String?,
        availableFrom: json['available_from'] is String
            ? parseApiDate(json['available_from'] as String)
            : null,
        availableTo: json['available_to'] is String
            ? parseApiDate(json['available_to'] as String)
            : null,
        items: [
          for (final e in json['items'] as List? ?? const [])
            SeriesPoint.fromJson(e as Map<String, dynamic>),
        ],
      );

  Map<String, dynamic> toJson() => {
    'model': model?.toJson(),
    'retraining': retraining,
    'message': message,
    'available_from': availableFrom == null ? null : apiDate(availableFrom!),
    'available_to': availableTo == null ? null : apiDate(availableTo!),
    'items': [for (final i in items) i.toJson()],
  };

  EvaluationSeries savedOn(DateTime saved) => EvaluationSeries(
    items: items,
    model: model,
    retraining: retraining,
    message: message,
    availableFrom: availableFrom,
    availableTo: availableTo,
    savedAt: saved,
  );
}
