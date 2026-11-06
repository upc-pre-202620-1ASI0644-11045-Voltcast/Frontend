import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../data/dataset.dart';
import '../data/datasets_repository.dart';

/// Uploaded files. While any is `raw` or `cleaning`, or a training runs, each
/// one is asked for every [pollEvery]; the polling stops by itself when nothing
/// is in progress. A file waiting for confirmation is not polled: only the user moves it.
class DatasetsController extends ChangeNotifier {
  DatasetsController(
    this._repository, {
    this.pollEvery = const Duration(seconds: 10),
  });

  final DatasetsRepository _repository;
  final Duration pollEvery;

  List<Dataset> _items = [];
  bool _loading = false;
  bool _loadedOnce = false;
  String? _error;
  bool _trainingRunning = false;
  Timer? _timer;

  List<Dataset> get items => _items;
  bool get loading => _loading;
  bool get hasLoaded => _loadedOnce;
  String? get error => _error;

  /// Uploads are refused while true.
  bool get trainingRunning => _trainingRunning;

  Dataset? byId(int id) {
    for (final d in _items) {
      if (d.id == id) return d;
    }
    return null;
  }

  Future<void> load() async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _items = await _repository.list();
      _loadedOnce = true;
      await _refreshTraining();
      _schedule();
    } on ApiException catch (e) {
      _error = e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Rethrows [ApiException] (the 400 causes) for the screen to show.
  Future<Dataset> upload(
    String filename,
    List<int> bytes, {
    int? baseDatasetId,
  }) async {
    final dataset = await _repository.upload(
      filename,
      bytes,
      baseDatasetId: baseDatasetId,
    );
    _replace(dataset);
    _schedule();
    return dataset;
  }

  /// Accepts the merge; the file is processed again and polled until final.
  Future<void> confirm(int id) async {
    _replace(await _repository.confirm(id));
    _schedule();
  }

  Future<void> _refreshTraining() async {
    try {
      _trainingRunning = await _repository.trainingRunning();
    } on ApiException {
      // Keep the last known value; the backend still refuses a bad upload.
    }
  }

  /// The detail has the `summary` the list lacks.
  Future<void> refresh(int id) async {
    try {
      _replace(await _repository.get(id));
    } on ApiException catch (e) {
      _error = e.message;
    }
    notifyListeners();
  }

  void _replace(Dataset fresh) {
    final merged = fresh.withSummaryFrom(byId(fresh.id));
    final known = byId(fresh.id) != null;
    _items = known
        ? [for (final d in _items) d.id == merged.id ? merged : d]
        : [merged, ..._items];
    notifyListeners();
  }

  void _schedule() {
    final pending = _trainingRunning || _items.any((d) => d.isProcessing);
    if (!pending) {
      _timer?.cancel();
      _timer = null;
    } else {
      _timer ??= Timer.periodic(pollEvery, (_) => _poll());
    }
  }

  Future<void> _poll() async {
    for (final d in _items.where((d) => d.isProcessing).toList()) {
      try {
        _replace(await _repository.get(d.id));
      } on ApiException {
        // Keep the last known state; the next tick tries again.
      }
    }
    await _refreshTraining();
    notifyListeners();
    _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
