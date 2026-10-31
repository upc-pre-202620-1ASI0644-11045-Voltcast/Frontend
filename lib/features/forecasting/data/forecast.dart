import '../../../core/format.dart';

class ModelInfo {
  const ModelInfo({
    required this.id,
    required this.name,
    required this.version,
  });

  final int id;
  final String name;
  final String version;

  factory ModelInfo.fromJson(Map<String, dynamic> json) => ModelInfo(
    id: json['id'] as int,
    name: json['name'] as String,
    version: json['version'] as String,
  );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'version': version};

  static ModelInfo? maybe(Object? json) =>
      json is Map<String, dynamic> ? ModelInfo.fromJson(json) : null;
}

class ForecastItem {
  const ForecastItem({
    required this.cellId,
    required this.cellName,
    required this.date,
    required this.voltage,
    required this.exceeds,
    this.maxVoltage,
  });

  final int cellId;
  final String cellName;
  final DateTime date;
  final double voltage;

  /// Allowed voltage for the cell; null when no limit is set.
  final double? maxVoltage;
  final bool exceeds;

  factory ForecastItem.fromJson(Map<String, dynamic> json) => ForecastItem(
    cellId: json['cell_id'] as int,
    cellName: json['cell_name'] as String,
    date: parseApiDate(json['date'] as String),
    voltage: (json['voltage'] as num).toDouble(),
    maxVoltage: (json['max_voltage'] as num?)?.toDouble(),
    exceeds: json['exceeds'] as bool,
  );

  Map<String, dynamic> toJson() => {
    'cell_id': cellId,
    'cell_name': cellName,
    'date': apiDate(date),
    'voltage': voltage,
    'max_voltage': maxVoltage,
    'exceeds': exceeds,
  };
}

class ForecastResult {
  const ForecastResult({
    required this.items,
    this.model,
    this.retraining = false,
    this.message,
    this.availableFrom,
    this.availableTo,
    this.savedAt,
  });

  /// Null while no model has been trained.
  final ModelInfo? model;

  /// A new version is being trained; these values come from the last one and stay valid.
  final bool retraining;
  final String? message;
  final DateTime? availableFrom;
  final DateTime? availableTo;
  final List<ForecastItem> items;

  /// Set when the data comes from the device (offline), with the day it was saved.
  final DateTime? savedAt;

  bool get isOffline => savedAt != null;

  factory ForecastResult.fromJson(Map<String, dynamic> json) => ForecastResult(
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
      for (final e in json['items'] as List)
        ForecastItem.fromJson(e as Map<String, dynamic>),
    ],
  );
}

/// Units: RMSE and MAE in V, MSE in V², MAPE in %, R² unitless. All null without data.
class ModelMetrics {
  const ModelMetrics({
    this.model,
    this.retraining = false,
    this.mse,
    this.rmse,
    this.mae,
    this.mape,
    this.r2,
    this.savedAt,
  });

  final ModelInfo? model;
  final bool retraining;
  final double? mse, rmse, mae, mape, r2;

  /// Set when the data comes from the device (offline), with the day it was saved.
  final DateTime? savedAt;

  Map<String, dynamic> toJson() => {
    'model': model?.toJson(),
    'retraining': retraining,
    'mse': mse,
    'rmse': rmse,
    'mae': mae,
    'mape': mape,
    'r2': r2,
  };

  ModelMetrics savedOn(DateTime day) => ModelMetrics(
    model: model,
    retraining: retraining,
    mse: mse,
    rmse: rmse,
    mae: mae,
    mape: mape,
    r2: r2,
    savedAt: day,
  );

  factory ModelMetrics.fromJson(Map<String, dynamic> json) => ModelMetrics(
    model: ModelInfo.maybe(json['model']),
    retraining: json['retraining'] as bool? ?? false,
    mse: (json['mse'] as num?)?.toDouble(),
    rmse: (json['rmse'] as num?)?.toDouble(),
    mae: (json['mae'] as num?)?.toDouble(),
    mape: (json['mape'] as num?)?.toDouble(),
    r2: (json['r2'] as num?)?.toDouble(),
  );
}
