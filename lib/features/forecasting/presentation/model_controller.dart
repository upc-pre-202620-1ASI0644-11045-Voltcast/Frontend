import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/evaluation.dart';
import '../data/evaluation_cache.dart';
import '../data/forecast.dart';
import '../data/forecasting_repository.dart';

/// Accuracy of the active model: the summary figures and the table of forecast
/// against measured voltage for one day. Without network it shows what the
/// device saved, only for days queried before.
class ModelController extends ChangeNotifier {
  ModelController(this._repository);

  final ForecastingRepository _repository;

  ModelMetrics? _metrics;
  EvaluationResult? _evaluation;
  DateTime? _date;
  String _order = 'worst';
  bool _loading = false;
  bool _evaluating = false;
  bool _offline = false;
  bool _canExportOffline = false;
  String? _error;
  String? _evaluationError;
  List<DateTime> _offlineDates = [];
  int _seq = 0;

  ModelMetrics? get metrics => _metrics;

  /// The last table (kept while the next one loads, so it never flashes empty).
  EvaluationResult? get evaluation => _evaluation;
  DateTime? get date => _date;

  /// `worst` or `best`.
  String get order => _order;

  /// First load of the screen.
  bool get loading => _loading;

  /// A table is being asked for.
  bool get evaluating => _evaluating;
  bool get offline => _offline;

  /// Why the screen cannot be shown at all (not a network failure).
  String? get error => _error;

  /// Why the table could not be shown (a refused date, a server failure).
  String? get evaluationError => _evaluationError;

  bool get noModel => _metrics != null && _metrics!.model == null;
  bool get retraining =>
      (_metrics?.retraining ?? false) || (_evaluation?.retraining ?? false);

  /// Offline and nothing was ever saved.
  bool get noOfflineData => _offline && _metrics == null && _evaluation == null;

  /// When the data shown was saved, only offline.
  DateTime? get savedAt => _evaluation?.savedAt ?? _metrics?.savedAt;

  /// The 300-row file can be made: online always, offline only if that day was saved so.
  bool get canExport =>
      _evaluation?.date != null &&
      _evaluation!.items.isNotEmpty &&
      (!_offline || _canExportOffline);

  bool isSelectable(DateTime day) {
    if (_offline) return _offlineDates.any((d) => d == day);
    final from = _evaluation?.availableFrom, to = _evaluation?.availableTo;
    if (from == null || to == null) return false;
    return !day.isBefore(from) && !day.isAfter(to);
  }

  /// First and last day the picker may show, or null when there is none.
  ({DateTime first, DateTime last})? get selectableRange {
    if (_offline) {
      return _offlineDates.isEmpty
          ? null
          : (first: _offlineDates.first, last: _offlineDates.last);
    }
    final from = _evaluation?.availableFrom, to = _evaluation?.availableTo;
    return from == null || to == null ? null : (first: from, last: to);
  }

  EvaluationCache get _cache => _repository.evaluationCache;

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _metrics = await _repository.metrics();
      _offline = false;
    } on ApiException catch (e) {
      if (e.isOffline) {
        _offline = true;
        _metrics = await _cache.metrics();
      } else {
        _error = e.message;
      }
    }
    if (_error == null && !noModel) await _loadEvaluation();
    _loading = false;
    notifyListeners();
  }

  Future<void> setDate(DateTime day) {
    _date = day;
    return _loadEvaluation();
  }

  Future<void> setOrder(String order) {
    if (order == _order) return Future.value();
    _order = order;
    return _loadEvaluation();
  }

  Future<void> retryEvaluation() => _loadEvaluation();

  Future<void> _loadEvaluation() async {
    final seq = ++_seq;
    _evaluating = true;
    _evaluationError = null;
    notifyListeners();
    try {
      final result = await _repository.evaluation(date: _date, order: _order);
      if (seq != _seq) return;
      _evaluation = result;
      _date = result.date ?? _date;
      _offline = false;
    } on ApiException catch (e) {
      if (seq != _seq) return;
      if (e.isOffline) {
        await _fromDevice();
      } else if (e.statusCode == 400) {
        // The API refuses a date outside its range: say so and fall back into the range.
        _evaluationError =
            'No hay datos de comparación para esa fecha. Elige otra dentro del rango disponible.';
        _date = _clamp(_date);
      } else if (e.statusCode == 404) {
        _evaluationError = 'No se encontró la comparación solicitada.';
      } else {
        _evaluationError = e.message;
      }
    }
    if (seq != _seq) return;
    _evaluating = false;
    notifyListeners();
  }

  DateTime? _clamp(DateTime? day) {
    final from = _evaluation?.availableFrom, to = _evaluation?.availableTo;
    if (day == null || from == null || to == null) return _evaluation?.date;
    if (day.isBefore(from)) return from;
    if (day.isAfter(to)) return to;
    return day;
  }

  Future<void> _fromDevice() async {
    _offline = true;
    _offlineDates = await _cache.dates();
    final day = (_date != null && _offlineDates.contains(_date))
        ? _date
        : await _cache.lastViewedDate();
    _evaluation = day == null
        ? null
        : await _cache.evaluation(day, order: _order);
    _date = day;
    _canExportOffline = day != null && await _cache.hasAll(day);
  }

  /// Every cell of the chosen day, worst first, for the Excel file. Rethrows
  /// [ApiException]; offline it comes from the 300-row copy.
  Future<List<EvaluationItem>> allRows() async {
    final day = _evaluation!.date!;
    if (_offline) {
      final saved = await _cache.evaluation(
        day,
        limit: EvaluationCache.exportLimit,
      );
      return saved!.items;
    }
    final all = await _repository.evaluation(
      date: day,
      limit: EvaluationCache.exportLimit,
    );
    return all.items;
  }
}
