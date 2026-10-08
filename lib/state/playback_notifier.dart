import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../models/segment.dart';

/// Pemutar satu segmen pada satu waktu (toggle play/pause per segmen).
class PlaybackNotifier extends ChangeNotifier {
  final _player = AudioPlayer();
  int? _playingId;
  bool _paused = false;

  int? get playingId => _playingId;
  bool isPlaying(int id) => _playingId == id && !_paused;

  PlaybackNotifier() {
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _playingId = null;
        _paused = false;
        notifyListeners();
      }
    });
  }

  /// Putar segmen (atau pause jika sedang diputar). Pindah segmen lainnya
  /// menghentikan yang lama.
  Future<void> toggle(Segment segment) async {
    if (_playingId == segment.id) {
      if (_paused) {
        await _player.play();
        _paused = false;
      } else {
        await _player.pause();
        _paused = true;
      }
      notifyListeners();
      return;
    }

    await _player.stop();
    _playingId = null;
    _paused = false;

    try {
      await _player.setFilePath(segment.filePath);
      await _player.play();
      _playingId = segment.id;
    } catch (e) {
      debugPrint('Gagal memutar segmen ${segment.id}: $e');
    }
    notifyListeners();
  }

  /// Hentikan pemutaran sepenuhnya (sebelum rekam/undo/simpan).
  Future<void> stopAll() async {
    if (_playingId == null) return;
    await _player.stop();
    _playingId = null;
    _paused = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
