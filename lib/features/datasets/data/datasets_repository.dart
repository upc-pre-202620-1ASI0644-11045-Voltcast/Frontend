import '../../../core/network/api_client.dart';
import 'dataset.dart';

/// `/datasets` endpoints. Any signed-in user may use them.
class DatasetsRepository {
  DatasetsRepository(this._api);

  final ApiClient _api;

  /// Newest first.
  Future<List<Dataset>> list() async {
    final data = await _api.get('/datasets', auth: true) as List;
    return data
        .map((e) => Dataset.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Dataset> get(int id) async => Dataset.fromJson(
    await _api.get('/datasets/$id', auth: true) as Map<String, dynamic>,
  );

  /// 201 with the dataset in `raw` (or `awaiting_confirmation` when it complements
  /// [baseDatasetId]); 400 for an unsupported, empty or oversized file, or while a
  /// training is running.
  Future<Dataset> upload(
    String filename,
    List<int> bytes, {
    int? baseDatasetId,
  }) async => Dataset.fromJson(
    await _api.upload(
      '/datasets',
      field: 'file',
      filename: filename,
      bytes: bytes,
      fields: {if (baseDatasetId != null) 'base_dataset_id': '$baseDatasetId'},
    ) as Map<String, dynamic>,
  );

  /// Accepts the merge shown for a dataset (202); it goes back to `raw`.
  Future<Dataset> confirm(int id) async => Dataset.fromJson(
    await _api.post('/datasets/$id/confirm', auth: true) as Map<String, dynamic>,
  );

  /// Uploads are refused while a training runs, so the screen asks.
  Future<bool> trainingRunning() async {
    final data = await _api.get('/trainings', auth: true) as List;
    return data.any((e) => (e as Map<String, dynamic>)['status'] == 'running');
  }
}
