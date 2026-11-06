import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../cells/data/cell.dart';
import '../data/forecast.dart';
import '../data/forecasting_repository.dart';

/// One day of forecasts for every cell. The day is always asked alone (about
/// 300 rows); the app never requests a long range for all cells.
/// Without network it shows what the device saved, and only for days seen before.
class ForecastsController extends ChangeNotifier {
  ForecastsController(this._repository, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final ForecastingRepository _repository;
  final DateTime Function() _clock;

  ForecastResult? _result;
  DateTime? _date;
  bool _onlyExceeds = false;
  String _query = '';
  bool _loading = false;
  String? _error;
  int _seq = 0;
  List<DateTime> _offlineDates = [];

  /// The last answer (null before the first one, or offline without data).
  ForecastResult? get result => _result;
  DateTime? get date => _date;
  bool get onlyExceeds => _onlyExceeds;
  bool get loading => _loading;
  String? get error => _error;
  DateTime get today {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  /// The answer comes from the device.
  bool get offline => _result?.isOffline ?? _offlineEmpty;
  bool _offlineEmpty = false;

  /// Offline and nothing saved for the date: "No existen pronósticos disponibles…".
  bool get noOfflineData => _offlineEmpty;

  DateTime? get availableFrom => _result?.availableFrom;
  DateTime? get availableTo => _result?.availableTo;
  bool get noModel => _result != null && _result!.model == null;

  /// Days the picker may offer: the available range online, the saved days offline.
  bool isSelectable(DateTime day) {
    if (offline) return _offlineDates.any((d) => d == day);
    final from = availableFrom, to = availableTo;
    if (from == null || to == null) return false;
    return !day.isBefore(from) && !day.isAfter(to);
  }

  /// First and last day the picker may show, or null when there is none.
  ({DateTime first, DateTime last})? get selectableRange {
    if (offline) {
      return _offlineDates.isEmpty
          ? null
          : (first: _offlineDates.first, last: _offlineDates.last);
    }
    final from = availableFrom, to = availableTo;
    return from == null || to == null ? null : (first: from, last: to);
  }

  List<ForecastItem> get items => _result?.items ?? const [];

  /// Items matching the search by cell name (A1, B12…), exceeding ones first, then by name.
  List<ForecastItem> get visible {
    final q = _query.trim().toLowerCase();
    final list = items
        .where((i) => q.isEmpty || i.cellName.toLowerCase().contains(q))
        .toList();
    list.sort((a, b) {
      if (a.exceeds != b.exceeds) return a.exceeds ? -1 : 1;
      return compareCellNames(a.cellName, b.cellName);
    });
    return list;
  }

  Future<void> load() => _fetch(_date);

  Future<void> setDate(DateTime day) => _fetch(day);

  Future<void> setOnlyExceeds(bool value) {
    _onlyExceeds = value;
    return _fetch(_date);
  }

  void setQuery(String value) {
    _query = value;
    notifyListeners();
  }

  Future<void> _fetch(DateTime? day) async {
    final seq = ++_seq;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final result = await _repository.forecasts(
        from: day,
        exceeds: _onlyExceeds ? true : null,
      );
      if (seq != _seq) return;
      _result = result;
      _offlineEmpty = false;
      // Without a date the backend answers the first available day.
      _date =
          day ??
          (result.items.isEmpty
              ? result.availableFrom
              : result.items.first.date);
    } on ApiException catch (e) {
      if (seq != _seq) return;
      if (e.isOffline) {
        await _useSavedCopy(day);
      } else {
        _error = e.message;
      }
    } finally {
      if (seq == _seq) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _useSavedCopy(DateTime? day) async {
    final cache = _repository.cache;
    _offlineDates = await cache.dates();
    final target = day ?? await cache.lastViewedDate();
    final saved = target == null
        ? null
        : await cache.day(target, exceeds: _onlyExceeds ? true : null);
    _date = target;
    _result = saved;
    _offlineEmpty = saved == null;
  }
}
