import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/segment.dart';
import '../services/native_service.dart';
import '../services/recorder_service.dart';
import '../utils/format.dart';

enum RecordMode { hold, toggle }

/// State pusat: daftar segmen, mode rekam, timer.
///
/// Tiap segmen = 1 file .m4a di temp dir. Undo membuang segmen terakhir.
/// Finalisasi menggabungkan semua segmen lalu menyimpan ke MediaStore.
class RecordingNotifier extends ChangeNotifier {
  RecordingNotifier(this._recorder, this._native);

  final RecorderService _recorder;
  final NativeService _native;

  final List<Segment> _segments = [];
  List<Segment> get segments => List.unmodifiable(_segments);

  /// Durasi segmen yang sedang direkam (live).
  final ValueNotifier<int> elapsed = ValueNotifier(0);

  /// Total durasi semua segmen (+ segmen berjalan).
  final ValueNotifier<int> total = ValueNotifier(0);

  RecordMode mode = RecordMode.hold;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  bool get canUndo => _segments.isNotEmpty && !_isRecording;
  bool get canFinish => _segments.isNotEmpty && !_isRecording;

  Segment? get lastSegment => _segments.isEmpty ? null : _segments.last;

  Timer? _timer;
  int _nextId = 1;

  void toggleMode() {
    if (_isRecording) return;
    mode = mode == RecordMode.hold ? RecordMode.toggle : RecordMode.hold;
    notifyListeners();
  }

  Future<bool> _ensurePermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Mulai segmen baru (tekan/tahan tombol rekam).
  Future<bool> startSegment() async {
    if (_isRecording) return false;
    if (!await _ensurePermission()) return false;

    final path = await _recorder.start();
    if (path == null) return false;

    _isRecording = true;
    elapsed.value = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      elapsed.value += 100;
      total.value += 100;
    });
    notifyListeners();
    return true;
  }

  /// Akhiri segmen (lepas tombol / ketuk stop).
  Future<void> stopSegment() async {
    if (!_isRecording) return;

    final path = await _recorder.stop();
    _timer?.cancel();
    _timer = null;

    final duration = elapsed.value;
    elapsed.value = 0;
    _isRecording = false;

    if (path != null) {
      if (duration >= 300) {
        _segments.add(Segment(
          id: _nextId++,
          filePath: path,
          durationMs: duration,
          createdAt: DateTime.now(),
        ));
      } else {
        // Terlalu pendek (tap tak sengaja) -> buang, jangan masuk list.
        _deleteQuietly(path);
      }
    }
    _refreshTotal();
    notifyListeners();
  }

  /// Buang segmen terakhir beserta filenya.
  Future<void> undo() async {
    if (_isRecording || _segments.isEmpty) return;
    final removed = _segments.removeLast();
    _deleteQuietly(removed.filePath);
    _refreshTotal();
    notifyListeners();
  }

  /// Gabungkan semua segmen dan simpan ke MediaStore. Kembalikan uri/path hasil.
  Future<String?> finish() async {
    if (_isRecording || _segments.isEmpty) return null;

    final name = 'narasi_${stamp(DateTime.now())}.m4a';
    final dir = await getTemporaryDirectory();
    final outPath = p.join(dir.path, 'merge_$name');

    final ok = await _native.merge(
      _segments.map((s) => s.filePath).toList(),
      outPath,
    );
    if (!ok) return null;

    return _native.saveToMediaStore(outPath, name);
  }

  /// Bersihkan state setelah rekaman disimpan.
  void reset() {
    _segments.clear();
    _nextId = 1;
    elapsed.value = 0;
    _refreshTotal();
    notifyListeners();
  }

  void _refreshTotal() {
    total.value = _segments.fold(0, (sum, s) => sum + s.durationMs);
  }

  void _deleteQuietly(String path) {
    try {
      final f = File(path);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }
}
