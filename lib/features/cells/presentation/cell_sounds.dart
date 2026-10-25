import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Lock and unlock sounds of the cells on the production line.
abstract final class CellSounds {
  /// Widget tests have no audio backend: they turn the sounds off.
  @visibleForTesting
  static bool enabled = true;

  static const _open = 'sounds/open_cell.mp3';
  static const _close = 'sounds/close_cell.mp3';

  /// One player per sound, loaded once and replayed from the start each time.
  static final _players = <String, Future<AudioPlayer>>{};

  static Future<void> open() => _play(_open);

  static Future<void> close() => _play(_close);

  /// Loads both sounds ahead of the first tap.
  static Future<void> preload() async {
    if (!enabled) return;
    for (final asset in [_open, _close]) {
      await _guard(asset, () => _load(asset));
    }
  }

  static Future<AudioPlayer> _load(String asset) => _players.putIfAbsent(asset, () async {
    final player = AudioPlayer();
    await player.setPlayerMode(PlayerMode.lowLatency);
    // The default releases the sound when it ends, so it would only play once.
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setSource(AssetSource(asset));
    return player;
  });

  static Future<void> _play(String asset) async {
    if (!enabled) return;
    await _guard(asset, () async {
      final player = await _load(asset);
      await player.stop(); // back to the start, also if it is still playing
      await player.resume();
    });
  }

  /// A missing or failing audio backend must never break opening a cell; the
  /// failed player is dropped so the next attempt loads it again.
  static Future<void> _guard(String asset, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _players.remove(asset);
      debugPrint('Cell sound failed: $e');
    }
  }
}
