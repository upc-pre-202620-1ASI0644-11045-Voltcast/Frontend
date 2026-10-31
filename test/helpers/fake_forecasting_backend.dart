import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Stand-in for the datasets, trainings, forecasts and alert-rules endpoints.
class FakeForecastingBackend {
  FakeForecastingBackend() {
    client = MockClient(_handle);
  }

  late final MockClient client;
  final requests = <http.Request>[];

  /// Every request fails as if there were no network.
  bool offline = false;

  /// `/alert-rules` POST answers 403 (the user is not a supervisor).
  bool forbidden = false;

  /// Every request answers this status (e.g. 500).
  int? failStatus;
  bool noModel = false;
  bool retraining = false;

  /// `/forecasts/evaluation` has no rows to compare.
  bool noComparison = false;

  /// First and last forecast day (180 days).
  final from = DateTime(2026, 11, 1);
  final to = DateTime(2027, 4, 29);

  /// Name -> id. A7 always exceeds its limit; B1 has no limit at all.
  final cells = {'A1': 1, 'A7': 2, 'B1': 3, 'B12': 4};

  final datasets = <Map<String, dynamic>>[
    dataset(2, 'historico_oct.xlsx', 'ready'),
    dataset(
      1,
      'historico_sep.xlsx',
      'failed',
      error: 'No cell columns were identified',
    ),
  ];
  final trainings = <Map<String, dynamic>>[];
  final rules = <Map<String, dynamic>>[
    {'id': 1, 'cell_id': null, 'max_voltage': 4.5, 'is_active': true},
  ];

  static Map<String, dynamic> dataset(
    int id,
    String name,
    String status, {
    String? error,
  }) => {
    'id': id,
    'filename': name,
    'upload_status': status,
    'error_message': error,
    'row_count': 1000,
    'processed_row_count': status == 'ready' ? 1000 : 0,
    'created_at': '2026-10-28T14:32:00',
  };

  static Map<String, dynamic> training(
    int id,
    String status, {
    String? finished,
  }) => {
    'id': id,
    'model_id': 1,
    'dataset_id': 2,
    'status': status,
    'rmse': status == 'success' ? 0.081 : null,
    'mae': status == 'success' ? 0.064 : null,
    'mape': status == 'success' ? 2.3 : null,
    'r2': status == 'success' ? 0.93 : null,
    'started_at': '2026-10-28T10:00:00',
    'finished_at': finished,
    'executed_by': 1,
  };

  http.Response _json(int status, Object body) => http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );

  Map<String, dynamic> _summary() => {
    'sections': {'A': 150, 'B': 150},
    'n_cells': 300,
    'date_from': '2024-01-01',
    'date_to': '2026-09-30',
    'days': 1004,
    'new_cells': 2,
  };

  Map<String, dynamic> _mergeSummary(int baseId) => {
        'base': {'date_from': '2024-01-01', 'date_to': '2026-06-30'},
        'new': {'date_from': '2026-06-25', 'date_to': '2026-09-30'},
        'gap_days': 0,
        'overlap_days': 6,
        'merged_days': 1004,
        'base_dataset_id': baseId,
      };

  /// 60 validation days ending the day before the forecasts start.
  DateTime get evalTo => from.subtract(const Duration(days: 3));
  DateTime get evalFrom => evalTo.subtract(const Duration(days: 59));

  http.Response _evaluation(Map<String, String> q) {
    final date = q['date'] == null ? evalTo : DateTime.parse(q['date']!);
    if (date.isBefore(evalFrom) || date.isAfter(evalTo)) {
      return _json(400, {'detail': 'The date is outside the available range'});
    }
    final limit = int.parse(q['limit'] ?? '10');
    final all = [
      for (final e in cells.entries)
        () {
          final real = 3.1 + e.value * 0.01;
          final predicted = real + e.value * 0.004 * (date.day.isEven ? 1 : -1);
          return {
            'cell_id': e.value,
            'cell_name': e.key,
            'real': real,
            'predicted': predicted,
            'error_v': (predicted - real).abs(),
            'error_pct': (predicted - real).abs() / real * 100,
          };
        }(),
    ]..sort((a, b) => (q['order'] == 'best' ? 1 : -1) * (a['error_pct'] as double).compareTo(b['error_pct'] as double));
    final mean = all.fold<double>(0, (n, i) => n + (i['error_pct'] as double)) / all.length;
    return _json(200, {
      'model': noModel ? null : {'id': 1, 'name': 'BiLSTM + XGBoost', 'version': 'v4.2'},
      'retraining': retraining,
      'message': null,
      'available_from': noModel ? null : _iso(evalFrom),
      'available_to': noModel ? null : _iso(evalTo),
      'date': noModel ? null : _iso(date),
      'total_cells': noModel || noComparison ? 0 : all.length,
      'mean_error_pct': noModel || noComparison ? null : mean,
      'items': noModel || noComparison ? [] : all.take(limit).toList(),
    });
  }

  Map<String, dynamic> _item(String name, DateTime day) {
    final id = cells[name]!;
    final voltage = name == 'A7'
        ? 4.71
        : 3.1 + id * 0.01 + (day.day % 5) * 0.01;
    final max = name == 'B1'
        ? null
        : (rules.where((r) => r['cell_id'] == id).firstOrNull?['max_voltage'] ??
              4.5);
    return {
      'cell_id': id,
      'cell_name': name,
      'date': _iso(day),
      'voltage': voltage,
      'max_voltage': max,
      'exceeds': max != null && voltage > (max as num),
    };
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  http.Response _forecasts(Map<String, String> q) {
    final dateFrom = q['date_from'] == null
        ? from
        : DateTime.parse(q['date_from']!);
    final dateTo = q['date_to'] == null
        ? dateFrom
        : DateTime.parse(q['date_to']!);
    if (dateTo.isBefore(dateFrom)) {
      return _json(400, {
        'detail': 'The end date cannot be before the start date',
      });
    }

    final items = <Map<String, dynamic>>[];
    if (!noModel) {
      for (
        var d = dateFrom;
        !d.isAfter(dateTo);
        d = d.add(const Duration(days: 1))
      ) {
        for (final name in cells.keys) {
          if (q['cell_id'] != null && cells[name] != int.parse(q['cell_id']!)) {
            continue;
          }
          final item = _item(name, d);
          if (q['exceeds'] != null &&
              item['exceeds'].toString() != q['exceeds']) {
            continue;
          }
          items.add(item);
        }
      }
    }
    return _json(200, {
      'model': noModel
          ? null
          : {'id': 1, 'name': 'BiLSTM + XGBoost', 'version': 'v4.2'},
      'retraining': retraining,
      'message': noModel ? 'No trained model is available yet' : null,
      'available_from': noModel ? null : _iso(from),
      'available_to': noModel ? null : _iso(to),
      'items': items,
    });
  }

  Future<http.Response> _handle(http.Request request) async {
    requests.add(request);
    if (offline) throw http.ClientException('no network');
    if (failStatus != null) {
      return _json(failStatus!, {'detail': 'Internal error: boom'});
    }

    final path = request.url.path.replaceFirst('/api/v1', '');
    final q = request.url.queryParameters;
    final get = request.method == 'GET';
    final body =
        request.headers['content-type']?.contains('json') == true &&
            request.body.isNotEmpty
        ? jsonDecode(request.body) as Map<String, dynamic>
        : <String, dynamic>{};

    if (get && path == '/cells') {
      return _json(200, [
        for (final e in cells.entries)
          {
            'id': e.value,
            'name': e.key,
            'is_active': true,
            'barcode_value': null,
          },
      ]);
    }
    if (get && path == '/components') return _json(200, []);

    // Datasets
    if (get && path == '/datasets') return _json(200, datasets);
    final ds = RegExp(r'^/datasets/(\d+)$').firstMatch(path);
    if (get && ds != null) {
      final d = datasets
          .where((d) => d['id'] == int.parse(ds.group(1)!))
          .firstOrNull;
      if (d == null) return _json(404, {'detail': 'Dataset not found'});
      return _json(200, {
        ...d,
        if (d['upload_status'] == 'ready') 'summary': _summary(),
        if (d['upload_status'] == 'awaiting_confirmation')
          'summary': _mergeSummary(d['base_dataset_id'] as int),
      });
    }
    final confirm = RegExp(r'^/datasets/(\d+)/confirm$').firstMatch(path);
    if (request.method == 'POST' && confirm != null) {
      final d = datasets.firstWhere((d) => d['id'] == int.parse(confirm.group(1)!));
      d['upload_status'] = 'raw';
      return _json(202, d);
    }
    if (request.method == 'POST' && path == '/datasets') {
      if (trainings.any((t) => t['status'] == 'running')) {
        return _json(400, {
          'detail': 'A training is in progress; wait for it to finish before uploading a new file',
        });
      }
      final name =
          RegExp(r'filename="(.+?)"').firstMatch(request.body)?.group(1) ?? '';
      if (!name.endsWith('.xlsx') && !name.endsWith('.xlsm')) {
        return _json(400, {
          'detail': "Unsupported file format '.csv'. Upload an Excel file (.xlsm, .xlsx)",
        });
      }
      final base = RegExp(r'name="base_dataset_id"\s+(\d+)').firstMatch(request.body)?.group(1);
      final created = {
        ...dataset(datasets.length + 1, name, base == null ? 'raw' : 'awaiting_confirmation'),
        'base_dataset_id': base == null ? null : int.parse(base),
      };
      datasets.insert(0, created);
      return _json(201, created);
    }

    // Trainings
    if (get && path == '/trainings') return _json(200, trainings);
    if (request.method == 'POST' && path == '/trainings') {
      if (trainings.any((t) => t['status'] == 'running')) {
        return _json(400, {'detail': 'A training is already in progress'});
      }
      final created = {
        ...training(trainings.length + 1, 'running'),
        'dataset_id': body['dataset_id'],
      };
      trainings.insert(0, created);
      return _json(202, created);
    }

    // Forecasts
    if (get && path == '/forecasts') return _forecasts(q);
    if (get && path == '/forecasts/evaluation') return _evaluation(q);
    if (get && path == '/forecasts/metrics') {
      return _json(200, {
        'model': noModel
            ? null
            : {'id': 1, 'name': 'BiLSTM + XGBoost', 'version': 'v4.2'},
        'retraining': retraining,
        'message': null,
        'mse': noModel ? null : 0.0066,
        'rmse': noModel ? null : 0.081,
        'mae': noModel ? null : 0.064,
        'mape': noModel ? null : 2.3,
        'r2': noModel ? null : 0.93,
      });
    }

    // Alert rules
    if (get && path == '/alert-rules') return _json(200, rules);
    if (request.method == 'POST' && path == '/alert-rules') {
      if (forbidden) return _json(403, {'detail': 'Admin privileges required'});
      rules.removeWhere((r) => r['cell_id'] == body['cell_id']);
      final created = {
        'id': rules.length + 10,
        'cell_id': body['cell_id'],
        'max_voltage': body['max_voltage'],
        'is_active': true,
      };
      rules.add(created);
      return _json(201, created);
    }
    return _json(404, {'detail': 'Not found'});
  }
}
