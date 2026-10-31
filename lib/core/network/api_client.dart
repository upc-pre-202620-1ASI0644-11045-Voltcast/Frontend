import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';
import 'backend_messages.dart';

typedef _FilePart = ({
  String field,
  String filename,
  List<int> bytes,
  Map<String, String> fields,
});

class ApiClient {
  ApiClient({required TokenStorage tokenStorage, http.Client? httpClient})
    : _tokens = tokenStorage,
      _http = httpClient ?? http.Client();

  final TokenStorage _tokens;
  final http.Client _http;

  /// Called when the refresh token is rejected, so the app can go to login.
  void Function()? onSessionExpired;

  Future<dynamic> get(String path, {bool auth = false}) =>
      _send('GET', path, auth: auth);

  Future<dynamic> post(String path, {Object? body, bool auth = false}) =>
      _send('POST', path, body: body, auth: auth);

  /// `multipart/form-data` with a single file part and optional text [fields].
  Future<dynamic> upload(
    String path, {
    required String field,
    required String filename,
    required List<int> bytes,
    Map<String, String> fields = const {},
  }) => _send(
    'POST',
    path,
    auth: true,
    file: (field: field, filename: filename, bytes: bytes, fields: fields),
  );

  Future<dynamic> put(String path, {Object? body, bool auth = false}) =>
      _send('PUT', path, body: body, auth: auth);

  Future<dynamic> patch(String path, {Object? body, bool auth = false}) =>
      _send('PATCH', path, body: body, auth: auth);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool auth = false,
    _FilePart? file,
  }) async {
    var response = await _request(
      method,
      path,
      body: body,
      auth: auth,
      file: file,
    );

    if (response.statusCode == 401 && auth && await _refreshAccessToken()) {
      response = await _request(
        method,
        path,
        body: body,
        auth: auth,
        file: file,
      );
    }
    return _decode(response);
  }

  Future<http.Response> _request(
    String method,
    String path, {
    Object? body,
    required bool auth,
    _FilePart? file,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}${ApiConfig.apiPrefix}$path');
    final http.BaseRequest request;
    if (file != null) {
      request = http.MultipartRequest(method, uri)
        ..fields.addAll(file.fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            file.field,
            file.bytes,
            filename: file.filename,
          ),
        );
    } else {
      request = http.Request(method, uri);
      if (body != null) {
        request.headers['Content-Type'] = 'application/json';
        (request as http.Request).body = jsonEncode(body);
      }
    }
    request.headers['Accept'] = 'application/json';
    if (auth) {
      final token = await _tokens.accessToken;
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
    }

    try {
      final streamed = await _http
          .send(request)
          .timeout(ApiConfig.requestTimeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException {
      throw const ApiException(
        'El servidor no respondió. Revisa tu conexión e inténtalo de nuevo.',
      );
    } on http.ClientException {
      throw const ApiException(
        'No se pudo conectar con el servidor. Verifica que esté en ejecución.',
      );
    }
  }

  /// Exchanges the refresh token for a new access token. Returns false (and
  /// signals session expiry) when the backend rejects it.
  Future<bool> _refreshAccessToken() async {
    final refresh = await _tokens.refreshToken;
    if (refresh == null) return false;

    try {
      final response = await _request(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': refresh},
        auth: false,
      );
      if (response.statusCode != 200) {
        await _tokens.clear();
        onSessionExpired?.call();
        return false;
      }
      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      await _tokens.saveTokens(access: data['access_token'] as String);
      return true;
    } on ApiException {
      // Network failure while refreshing: keep the tokens, fail the request.
      return false;
    }
  }

  dynamic _decode(http.Response response) {
    final text = utf8.decode(response.bodyBytes);
    final json = text.isEmpty ? null : _tryDecode(text);

    if (response.statusCode >= 200 && response.statusCode < 300) return json;

    throw ApiException(
      _messageFrom(json, response.statusCode),
      statusCode: response.statusCode,
    );
  }

  dynamic _tryDecode(String text) {
    try {
      return jsonDecode(text);
    } on FormatException {
      return null;
    }
  }

  /// FastAPI answers `{"detail": "msg"}` for HTTPException and
  /// `{"detail": [{"loc": [...], "msg": "..."}]}` for validation errors (422).
  String _messageFrom(dynamic json, int status) {
    final detail = json is Map<String, dynamic> ? json['detail'] : null;

    if (status == 403) return 'No tienes permisos para realizar esta acción.';

    if (detail is String) {
      if (status >= 500) return 'Error del servidor. Inténtalo más tarde.';
      return translateBackendMessage(detail);
    }
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] is String) {
        return 'Datos inválidos: ${first['msg']}';
      }
    }
    return status >= 500
        ? 'Error del servidor. Inténtalo más tarde.'
        : 'Ocurrió un error inesperado ($status).';
  }

  void close() => _http.close();
}
