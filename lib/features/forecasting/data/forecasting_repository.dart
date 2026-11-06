import '../../../core/format.dart';
import '../../../core/network/api_client.dart';
import 'alert_rule.dart';
import 'evaluation.dart';
import 'evaluation_cache.dart';
import 'evaluation_series.dart';
import 'forecast.dart';
import 'forecast_cache.dart';

/// Forecasts, model accuracy, training start and voltage limits.
class ForecastingRepository {
  ForecastingRepository(
    this._api, {
    ForecastCache? cache,
    EvaluationCache? evaluationCache,
  }) : cache = cache ?? ForecastCache(),
       evaluationCache = evaluationCache ?? EvaluationCache();

  final ApiClient _api;

  /// Offline copy of every forecast response.
  final ForecastCache cache;

  /// Offline copy of the accuracy screen.
  final EvaluationCache evaluationCache;

  /// Without dates the backend answers the first available day; with only [from], that day;
  /// with both, the range. Never ask a long range for every cell (9 000 rows a month).
  Future<ForecastResult> forecasts({
    DateTime? from,
    DateTime? to,
    int? cellId,
    bool? exceeds,
  }) async {
    final query = {
      if (from != null) 'date_from': apiDate(from),
      if (to != null) 'date_to': apiDate(to),
      if (cellId != null) 'cell_id': '$cellId',
      if (exceeds != null) 'exceeds': '$exceeds',
    };
    final path = Uri(
      path: '/forecasts',
      queryParameters: query.isEmpty ? null : query,
    ).toString();
    final result = ForecastResult.fromJson(
      await _api.get(path, auth: true) as Map<String, dynamic>,
    );
    await cache.save(result, cellId: cellId, exceeds: exceeds);
    return result;
  }

  Future<ModelMetrics> metrics() async {
    final metrics = ModelMetrics.fromJson(
      await _api.get('/forecasts/metrics', auth: true) as Map<String, dynamic>,
    );
    await evaluationCache.saveMetrics(metrics);
    return metrics;
  }

  /// Forecast against measured voltage for one validation day. Without [date] the
  /// API answers its default day. `order` is `worst` or `best`; 400 for a date
  /// outside the available range.
  Future<EvaluationResult> evaluation({
    DateTime? date,
    int limit = 10,
    String order = 'worst',
  }) async {
    final path = Uri(
      path: '/forecasts/evaluation',
      queryParameters: {
        if (date != null) 'date': apiDate(date),
        'limit': '$limit',
        'order': order,
      },
    ).toString();
    final result = EvaluationResult.fromJson(
      await _api.get(path, auth: true) as Map<String, dynamic>,
    );
    await evaluationCache.saveEvaluation(result, limit: limit, order: order);
    return result;
  }

  /// Mean error of every validation day, in one call. It does not depend on the
  /// day the table shows. 400 for a date outside the range (the app sends none).
  Future<EvaluationSeries> evaluationSeries() async {
    final series = EvaluationSeries.fromJson(
      await _api.get('/forecasts/evaluation/series', auth: true)
          as Map<String, dynamic>,
    );
    await evaluationCache.saveSeries(series);
    return series;
  }

  /// 202; 400 when one is already running or the dataset is not ready.
  Future<void> startTraining(int datasetId) =>
      _api.post('/trainings', body: {'dataset_id': datasetId}, auth: true);

  // ── Voltage limits ───────────────────────────────────────────────────────

  Future<List<AlertRule>> alertRules() async {
    final data = await _api.get('/alert-rules', auth: true) as List;
    return data
        .map((e) => AlertRule.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Sets the general limit; a new value replaces the previous one. Supervisor only
  /// (403 otherwise). The API also takes a `cell_id`, which the app no longer sends.
  Future<AlertRule> setLimit(double maxVoltage) async => AlertRule.fromJson(
    await _api.post(
      '/alert-rules',
      body: {'max_voltage': maxVoltage},
      auth: true,
    ) as Map<String, dynamic>,
  );
}
