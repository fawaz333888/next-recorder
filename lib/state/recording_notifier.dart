import 'dart:async';
import 'dart:convert';
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
    // Notification permission = POST_NOTIFICATIONS di Android 13+,
    // dibutuhkan agar foreground service menampilkan notif.
    await [Permission.microphone, Permission.notification].request();
    final mic = await Permission.microphone.status;
    return mic.isGranted;
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
      // Update teks notif tiap detik saja (hemat IPC).
      if (elapsed.value % 1000 == 0) {
        _native.updateForeground(_notifText());
      }
    });
    notifyListeners();
    return true;
  }

  /// Akhiri segmen (lepas tombol / ketuk stop / tombol Stop di notifikasi).
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
    _saveSession();
    notifyListeners();
  }

  /// Buang segmen terakhir beserta filenya.
  Future<void> undo() async {
    if (_isRecording || _segments.isEmpty) return;
    final removed = _segments.removeLast();
    _deleteQuietly(removed.filePath);
    _refreshTotal();
    _saveSession();
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

    final saved = await _native.saveToMediaStore(outPath, name);
    if (saved == null) return null;

    // File asli baru dihapus setelah MediaStore benar-benar sukses.
    _deleteQuietly(outPath);
    for (final s in _segments) {
      _deleteQuietly(s.filePath);
    }
    return saved;
  }

  /// Bersihkan state setelah rekaman disimpan.
  void reset() {
    _segments.clear();
    _nextId = 1;
    elapsed.value = 0;
    _refreshTotal();
    _saveSession();
    notifyListeners();
  }

  /// Muat sesi terakhir dari disk. Entry yang filenya hilang dibuang.
  Future<void> loadSession() async {
    try {
      final file = await _sessionFile;
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      mode = (json['mode'] as String?) == 'toggle'
          ? RecordMode.toggle
          : RecordMode.hold;
      _nextId = json['nextId'] as int? ?? 1;

      final list = json['segments'] as List? ?? [];
      for (final e in list) {
        final seg = Segment.fromJson(e as Map<String, dynamic>);
        if (File(seg.filePath).existsSync()) {
          _segments.add(seg);
        } else {
          debugPrint('Session: file segmen ${seg.id} hilang, dibuang');
        }
      }
      _refreshTotal();
      notifyListeners();
    } catch (e) {
      debugPrint('Gagal memuat sesi: $e');
    }
  }

  Future<void> _saveSession() async {
    try {
      final file = await _sessionFile;
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(jsonEncode({
        'mode': mode == RecordMode.toggle ? 'toggle' : 'hold',
        'nextId': _nextId,
        'segments': _segments.map((s) => s.toJson()).toList(),
      }));
    } catch (e) {
      debugPrint('Gagal menyimpan sesi: $e');
    }
  }

  Future<File> get _sessionFile async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'session.json'));
  }

  void _refreshTotal() {
    total.value = _segments.fold(0, (sum, s) => sum + s.durationMs);
  }

  String _notifText() =>
      'Segmen ${formatDuration(elapsed.value)} • Total ${formatDuration(total.value)}';

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
