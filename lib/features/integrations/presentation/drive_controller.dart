import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../data/drive_repository.dart';
import '../data/drive_status.dart';

/// Opens [uri] outside the app; false when nothing could open it.
typedef UrlOpener = Future<bool> Function(Uri uri);

Future<bool> openInBrowser(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

const offlineMessage = 'Sin conexión.';
const notConfiguredMessage =
    'Google Drive no está configurado en el servidor.';

/// The Google Drive connection shown in the screen. It keeps the last status it
/// got (also on the device) so something shows when there is no network.
class DriveController extends ChangeNotifier {
  DriveController(this._repository, {this.open = openInBrowser});

  final DriveRepository _repository;
  final UrlOpener open;

  DriveStatus? _status;
  DateTime? _savedAt;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String? _actionError;

  DriveStatus? get status => _status;

  /// When [status] was received; it can be old if the last load failed.
  DateTime? get savedAt => _savedAt;
  bool get loading => _loading;

  /// A connect or disconnect is in progress.
  bool get busy => _busy;

  /// Why the last load failed; [status] may still hold the previous one.
  String? get error => _error;

  /// Why the last connect or disconnect failed.
  String? get actionError => _actionError;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _status = await _repository.status();
      _savedAt = DateTime.now();
    } on ApiException catch (e) {
      if (_status == null) {
        final saved = await _repository.lastKnown();
        _status = saved?.status;
        _savedAt = saved?.savedAt;
      }
      _error = e.isOffline ? offlineMessage : e.message;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Opens Google's consent page in the browser. The code and tokens never
  /// reach the app: the backend takes them in its callback.
  Future<void> connect() async {
    if (_busy) return;
    await _run(() async {
      if (!await open(await _repository.connect())) {
        _actionError = 'No se pudo abrir el navegador.';
      }
    });
  }

  Future<void> disconnect() async {
    if (_busy) return;
    await _run(() async {
      await _repository.disconnect();
      await load();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    _busy = true;
    _actionError = null;
    notifyListeners();
    try {
      await action();
    } on ApiException catch (e) {
      _actionError = e.statusCode == 503 ? notConfiguredMessage : e.message;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
