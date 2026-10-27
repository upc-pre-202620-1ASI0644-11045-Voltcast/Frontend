import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A swap done while offline, waiting to be sent to the server. The original
/// cells are kept so the sync can tell whether the server still matches the
/// state the user saw (and whether a lost reply already applied the swap).
class PendingSwap {
  const PendingSwap({
    required this.aId,
    required this.bId,
    required this.aCellId,
    required this.bCellId,
    required this.aSerial,
    required this.bSerial,
  });

  final int aId;
  final int bId;

  /// Cells the components were in BEFORE the swap.
  final int aCellId;
  final int bCellId;
  final String aSerial;
  final String bSerial;

  String get label => '$aSerial ⇄ $bSerial';

  Map<String, dynamic> toJson() => {
        'aId': aId,
        'bId': bId,
        'aCellId': aCellId,
        'bCellId': bCellId,
        'aSerial': aSerial,
        'bSerial': bSerial,
      };

  factory PendingSwap.fromJson(Map<String, dynamic> json) => PendingSwap(
        aId: json['aId'] as int,
        bId: json['bId'] as int,
        aCellId: json['aCellId'] as int,
        bCellId: json['bCellId'] as int,
        aSerial: json['aSerial'] as String,
        bSerial: json['bSerial'] as String,
      );
}

/// Where the pending swaps survive an app restart.
abstract class PendingSwapStore {
  Future<List<PendingSwap>> read();
  Future<void> write(List<PendingSwap> swaps);
}

class PrefsPendingSwapStore implements PendingSwapStore {
  static const _key = 'pending_component_swaps';

  @override
  Future<List<PendingSwap>> read() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return [for (final e in list) PendingSwap.fromJson(e as Map<String, dynamic>)];
    } on Object {
      // A corrupted entry must not block the screen; start clean.
      return [];
    }
  }

  @override
  Future<void> write(List<PendingSwap> swaps) async {
    final prefs = await SharedPreferences.getInstance();
    if (swaps.isEmpty) {
      await prefs.remove(_key);
    } else {
      await prefs.setString(_key, jsonEncode([for (final s in swaps) s.toJson()]));
    }
  }
}

/// In-memory store for tests.
class MemoryPendingSwapStore implements PendingSwapStore {
  MemoryPendingSwapStore([List<PendingSwap>? initial]) : _swaps = [...?initial];

  List<PendingSwap> _swaps;

  @override
  Future<List<PendingSwap>> read() async => [..._swaps];

  @override
  Future<void> write(List<PendingSwap> swaps) async => _swaps = [...swaps];
}
