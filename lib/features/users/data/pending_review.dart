import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../auth/data/auth_user.dart';

/// A decision on an access request made while offline, waiting to be sent to
/// the server. The server sends the notification email when it receives it.
class PendingReview {
  const PendingReview({
    required this.userId,
    required this.approve,
    required this.fullName,
  });

  final int userId;
  final bool approve;

  /// Only to name the account in messages when the list is not at hand.
  final String fullName;

  /// "la aprobación" / "el rechazo".
  String get decisionLabel => approve ? 'la aprobación' : 'el rechazo';

  /// Whether the server already holds this same decision (a reply that was
  /// lost, or another supervisor deciding the same).
  bool isAppliedOn(AuthUser user) =>
      approve ? user.isActive : user.status == 'rejected';

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'approve': approve,
    'fullName': fullName,
  };

  factory PendingReview.fromJson(Map<String, dynamic> json) => PendingReview(
    userId: json['userId'] as int,
    approve: json['approve'] as bool,
    fullName: json['fullName'] as String,
  );
}

/// Where the pending decisions survive an app restart.
abstract class PendingReviewStore {
  Future<List<PendingReview>> read();
  Future<void> write(List<PendingReview> reviews);
}

/// One queue per supervisor: a decision is only ever sent with the session of
/// whoever made it. Another account on the same phone neither sees nor sends it.
class PrefsPendingReviewStore implements PendingReviewStore {
  PrefsPendingReviewStore(int supervisorId)
    : _key = 'pending_account_reviews_$supervisorId';

  final String _key;

  @override
  Future<List<PendingReview>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [
        for (final e in list) PendingReview.fromJson(e as Map<String, dynamic>),
      ];
    } on Object {
      // A corrupted entry must not block the screen; start clean.
      return [];
    }
  }

  @override
  Future<void> write(List<PendingReview> reviews) async {
    final prefs = await SharedPreferences.getInstance();
    if (reviews.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(
        _key,
        jsonEncode([for (final r in reviews) r.toJson()]),
      );
    }
  }
}

/// In-memory store for tests.
class MemoryPendingReviewStore implements PendingReviewStore {
  MemoryPendingReviewStore([List<PendingReview>? initial])
    : reviews = [...?initial];

  List<PendingReview> reviews;

  @override
  Future<List<PendingReview>> read() async => [...reviews];

  @override
  Future<void> write(List<PendingReview> reviews) async =>
      this.reviews = [...reviews];
}
