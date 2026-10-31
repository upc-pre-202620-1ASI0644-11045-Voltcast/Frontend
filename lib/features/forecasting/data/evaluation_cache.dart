import 'dart:convert';

import '../../../core/format.dart';
import 'evaluation.dart';
import 'forecast.dart';
import 'forecast_cache.dart';

/// Offline copy of the accuracy screen: the last metrics and every queried day.
/// A day keeps each answer as it was asked ("worst:10", "best:10", "worst:300").
class EvaluationCache {
  EvaluationCache({ForecastCacheStore? store})
    : _store = store ?? PrefsForecastCacheStore('evaluation_cache');

  /// shortcut: the oldest days are dropped past this many so the prefs string stays small
  /// (a 300-row day is about 35 KB); move to a database for a longer history.
  static const maxDays = 30;
  static const exportLimit = 300;

  final ForecastCacheStore _store;
  Map<String, dynamic>? _metrics;
  final _days = <String, Map<String, dynamic>>{};
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _store.read();
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _metrics = json['metrics'] as Map<String, dynamic>?;
      _days.addAll((json['days'] as Map<String, dynamic>).cast());
    } on Object {
      // A corrupted copy must not block the screen; start clean.
      _days.clear();
      _metrics = null;
    }
  }

  Future<void> _write() async {
    try {
      await _store.write(jsonEncode({'metrics': _metrics, 'days': _days}));
    } on Object {
      // The copy is a convenience; a failed write only loses it.
    }
  }

  Future<void> saveMetrics(ModelMetrics metrics, {DateTime? now}) async {
    if (metrics.model == null || metrics.mape == null) return;
    await _ensureLoaded();
    _metrics = {
      'saved': (now ?? DateTime.now()).toIso8601String(),
      'data': metrics.toJson(),
    };
    await _write();
  }

  Future<ModelMetrics?> metrics() async {
    await _ensureLoaded();
    final m = _metrics;
    if (m == null) return null;
    return ModelMetrics.fromJson(
      m['data'] as Map<String, dynamic>,
    ).savedOn(DateTime.parse(m['saved'] as String));
  }

  Future<void> saveEvaluation(
    EvaluationResult result, {
    required int limit,
    required String order,
    DateTime? now,
  }) async {
    final date = result.date;
    if (result.model == null || date == null || result.items.isEmpty) return;
    await _ensureLoaded();
    final at = (now ?? DateTime.now()).toIso8601String();
    final day = _days.putIfAbsent(apiDate(date), () => {});
    day['$order:$limit'] = {'saved': at, 'data': result.toJson()};
    day['saved'] = at;
    final oldest = _days.entries.toList()
      ..sort(
        (a, b) => (a.value['saved'] as String).compareTo(
          b.value['saved'] as String,
        ),
      );
    for (final e in oldest.take(
      (_days.length - maxDays).clamp(0, _days.length),
    )) {
      _days.remove(e.key);
    }
    await _write();
  }

  /// Days that were queried, oldest first.
  Future<List<DateTime>> dates() async {
    await _ensureLoaded();
    return [for (final k in _days.keys) parseApiDate(k)]..sort();
  }

  /// The day queried last: where to open without network.
  Future<DateTime?> lastViewedDate() async {
    await _ensureLoaded();
    if (_days.isEmpty) return null;
    final latest = _days.entries.reduce(
      (a, b) =>
          (a.value['saved'] as String).compareTo(b.value['saved'] as String) >=
              0
          ? a
          : b,
    );
    return parseApiDate(latest.key);
  }

  /// The day as it was asked, or reduced from the 300-row copy; null when never saved.
  Future<EvaluationResult?> evaluation(
    DateTime date, {
    int limit = 10,
    String order = 'worst',
  }) async {
    await _ensureLoaded();
    final day = _days[apiDate(date)];
    if (day == null) return null;
    final entry =
        (day['$order:$limit'] ?? day['worst:$exportLimit'])
            as Map<String, dynamic>?;
    if (entry == null) return null;
    return EvaluationResult.fromJson(
      entry['data'] as Map<String, dynamic>,
    ).top(limit, order, DateTime.parse(entry['saved'] as String));
  }

  /// The 300-row copy needed for the Excel file exists.
  Future<bool> hasAll(DateTime date) async {
    await _ensureLoaded();
    return _days[apiDate(date)]?['worst:$exportLimit'] != null;
  }
}
