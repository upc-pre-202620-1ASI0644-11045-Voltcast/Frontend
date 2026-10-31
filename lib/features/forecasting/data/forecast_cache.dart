import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/format.dart';
import 'forecast.dart';

/// Where the offline copy lives: one JSON string.
abstract class ForecastCacheStore {
  Future<String?> read();
  Future<void> write(String json);
}

class PrefsForecastCacheStore implements ForecastCacheStore {
  PrefsForecastCacheStore([this._key = 'forecast_cache']);

  final String _key;

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(_key);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(_key, json);
}

/// In-memory store for tests.
class MemoryForecastCacheStore implements ForecastCacheStore {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async => value = json;
}

class _Day {
  _Day(this.savedAt, {this.complete = false, Map<int, ForecastItem>? cells})
    : cells = cells ?? {};

  DateTime savedAt;

  /// Every cell of the day was saved (an unfiltered query), so the day can be shown whole.
  bool complete;
  final Map<int, ForecastItem> cells;
}

/// Forecasts kept on the device by day and by cell, for use without network.
class ForecastCache {
  ForecastCache({ForecastCacheStore? store})
    : _store = store ?? PrefsForecastCacheStore();

  /// shortcut: the oldest days are dropped past this many items so the prefs string stays small;
  /// move to a database if a longer offline history is needed.
  static const maxItems = 12000;

  final ForecastCacheStore _store;
  final _days = <String, _Day>{};
  ModelInfo? _model;
  DateTime? _from, _to;
  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _store.read();
      if (raw == null) return;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _model = ModelInfo.maybe(json['model']);
      _from = json['from'] is String
          ? parseApiDate(json['from'] as String)
          : null;
      _to = json['to'] is String ? parseApiDate(json['to'] as String) : null;
      for (final e in (json['days'] as Map<String, dynamic>).entries) {
        final day = e.value as Map<String, dynamic>;
        _days[e.key] = _Day(
          DateTime.parse(day['saved'] as String),
          complete: day['complete'] as bool,
          cells: {
            for (final i in day['cells'] as List)
              (i as Map<String, dynamic>)['cell_id'] as int:
                  ForecastItem.fromJson(i),
          },
        );
      }
    } on Object {
      // A corrupted copy must not block the screens; start clean.
      _days.clear();
    }
  }

  /// Remembers a successful response. A whole-day query (no cell, no filter)
  /// replaces that day; any other only adds its cells.
  Future<void> save(
    ForecastResult result, {
    int? cellId,
    bool? exceeds,
    DateTime? now,
  }) async {
    if (result.model == null || result.items.isEmpty) return;
    await _ensureLoaded();
    final at = now ?? DateTime.now();
    final whole = cellId == null && exceeds == null;
    final byDay = <String, List<ForecastItem>>{};
    for (final item in result.items) {
      byDay.putIfAbsent(apiDate(item.date), () => []).add(item);
    }
    for (final e in byDay.entries) {
      final day = _days.putIfAbsent(e.key, () => _Day(at));
      if (whole) day.cells.clear();
      for (final item in e.value) {
        day.cells[item.cellId] = item;
      }
      day.savedAt = at;
      day.complete = day.complete || whole;
    }
    _model = result.model;
    _from = result.availableFrom ?? _from;
    _to = result.availableTo ?? _to;
    _evict();
    try {
      await _store.write(jsonEncode(_toJson()));
    } on Object {
      // The copy is a convenience; a failed write only loses it.
    }
  }

  void _evict() {
    var total = _days.values.fold<int>(0, (n, d) => n + d.cells.length);
    final oldest = _days.entries.toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    for (final e in oldest) {
      if (total <= maxItems) break;
      total -= e.value.cells.length;
      _days.remove(e.key);
    }
  }

  Map<String, dynamic> _toJson() => {
    'model': _model?.toJson(),
    'from': _from == null ? null : apiDate(_from!),
    'to': _to == null ? null : apiDate(_to!),
    'days': {
      for (final e in _days.entries)
        e.key: {
          'saved': e.value.savedAt.toIso8601String(),
          'complete': e.value.complete,
          'cells': [for (final i in e.value.cells.values) i.toJson()],
        },
    },
  };

  /// Days that can be shown whole, oldest first.
  Future<List<DateTime>> dates() async {
    await _ensureLoaded();
    return [
      for (final e in _days.entries)
        if (e.value.complete) parseApiDate(e.key),
    ]..sort();
  }

  /// The day last saved whole: where to open without network.
  Future<DateTime?> lastViewedDate() async {
    await _ensureLoaded();
    final whole = _days.entries.where((e) => e.value.complete).toList()
      ..sort((a, b) => a.value.savedAt.compareTo(b.value.savedAt));
    return whole.isEmpty ? null : parseApiDate(whole.last.key);
  }

  /// A saved whole day, or null when it was never queried.
  Future<ForecastResult?> day(DateTime date, {bool? exceeds}) async {
    await _ensureLoaded();
    final day = _days[apiDate(date)];
    if (day == null || !day.complete) return null;
    return _result(
      day.cells.values
          .where((i) => exceeds == null || i.exceeds == exceeds)
          .toList(),
      day.savedAt,
    );
  }

  /// Every saved day of one cell, or null when none.
  Future<ForecastResult?> cell(int cellId) async {
    await _ensureLoaded();
    final items = <ForecastItem>[];
    DateTime? saved;
    for (final d in _days.values) {
      final item = d.cells[cellId];
      if (item == null) continue;
      items.add(item);
      if (saved == null || d.savedAt.isAfter(saved)) saved = d.savedAt;
    }
    if (items.isEmpty) return null;
    items.sort((a, b) => a.date.compareTo(b.date));
    return _result(items, saved!);
  }

  ForecastResult _result(List<ForecastItem> items, DateTime saved) =>
      ForecastResult(
        items: items,
        model: _model,
        availableFrom: _from,
        availableTo: _to,
        savedAt: saved,
      );
}
