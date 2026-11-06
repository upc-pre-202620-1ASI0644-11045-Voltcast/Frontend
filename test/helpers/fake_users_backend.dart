import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Tiny stateful stand-in for the backend's `/users` endpoints.
class FakeUsersBackend {
  FakeUsersBackend() {
    client = MockClient(_handle);
  }

  late final MockClient client;
  final requests = <http.Request>[];

  /// When set, every request fails with this status/detail.
  ({int status, String detail})? failWith;

  /// When set, only the approve/reject requests fail with this status/detail.
  ({int status, String detail})? failReviewWith;

  /// Every request fails as it does in airplane mode.
  bool offline = false;

  /// The next approve/reject is applied, but its reply never arrives.
  bool loseNextReviewReply = false;

  /// The approve/reject requests that reached the server.
  List<http.Request> get reviews =>
      requests.where((r) => r.url.path.endsWith('/approval')).toList();

  final users = <Map<String, dynamic>>[
    _user(1, 'Carlos Mendoza', 'c.mendoza@voltcast.io', 'active', 'ADMIN'),
    _user(2, 'Ana Ríos', 'a.rios@voltcast.io', 'active', 'USER'),
    _user(3, 'Sofía Vargas', 's.vargas@voltcast.io', 'disabled', 'USER'),
    _user(4, 'Mariana Torres', 'm.torres@empresa.com', 'pending', null),
    _user(5, 'Diego Salcedo', 'd.salcedo@empresa.com', 'pending', null),
    _user(6, 'Rechazado Uno', 'r.uno@empresa.com', 'rejected', null),
  ];

  static Map<String, dynamic> _user(int id, String name, String email, String status, String? role) => {
        'id': id,
        'email': email,
        'full_name': name,
        'role': role,
        'status': status,
        'created_at': '2026-01-12T10:00:00',
      };

  http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<http.Response> _handle(http.Request request) async {
    if (offline) throw http.ClientException('no network');
    requests.add(request);
    final fail = failWith;
    if (fail != null) return _json(fail.status, {'detail': fail.detail});

    final path = request.url.path.replaceFirst('/api/v1', '');
    if (request.method == 'GET' && path == '/users') {
      final status = request.url.queryParameters['status'];
      return _json(200, status == null ? users : users.where((u) => u['status'] == status).toList());
    }

    final match = RegExp(r'^/users/(\d+)(?:/(approval|status))?$').firstMatch(path);
    if (match == null) return _json(404, {'detail': 'Not found'});
    final user = users.firstWhere((u) => u['id'] == int.parse(match.group(1)!));
    final body = request.body.isEmpty ? <String, dynamic>{} : jsonDecode(request.body) as Map<String, dynamic>;

    switch (match.group(2)) {
      case 'approval':
        final refusal = failReviewWith;
        if (refusal != null) return _json(refusal.status, {'detail': refusal.detail});
        final approve = body['decision'] == 'approve';
        // The backend only reviews pending requests, so it can't email twice.
        if (user['status'] != 'pending') {
          return _json(400, {'detail': 'Only pending requests can be ${approve ? 'approved' : 'rejected'}'});
        }
        user['status'] = approve ? 'active' : 'rejected';
        user['role'] = approve ? body['role'] : null;
        if (loseNextReviewReply) {
          loseNextReviewReply = false;
          throw http.ClientException('connection lost');
        }
      case 'status':
        user['status'] = body['status'];
      default:
        if (body['full_name'] != null) user['full_name'] = body['full_name'];
        if (body['email'] != null) user['email'] = body['email'];
    }
    return _json(200, user);
  }
}
