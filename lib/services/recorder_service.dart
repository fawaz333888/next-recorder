import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'native_service.dart';

class RecorderService {
  final _recorder = AudioRecorder();
  final _native = NativeService();
  bool _recording = false;
  bool get isRecording => _recording;

  Future<bool> hasPermission() => _recorder.hasPermission();

  /// Mulai rekam segmen baru ke file temp .m4a.
  /// Foreground service dinyalakan bersamaan agar Android tidak membunuh
  /// proses saat app di-background / layar mati.
  Future<String?> start() async {
    if (_recording) return null;
    final dir = await getTemporaryDirectory();
    final path = p.join(
      dir.path,
      'seg_${DateTime.now().microsecondsSinceEpoch}.m4a',
    );
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
      ),
      path: path,
    );
    _recording = true;
    await _native.startForeground('Merekam…');
    return path;
  }

  /// Hentikan rekaman, kembalikan path file hasilnya.
  ///
  /// File dipindahkan dari temp dir ke dir persisten (segments/) supaya
  /// selamat dari pembunuhan proses oleh OS.
  Future<String?> stop() async {
    if (!_recording) return null;
    final tempPath = await _recorder.stop();
    _recording = false;
    await _native.stopForeground();
    if (tempPath == null) return null;
    return _persistSegmentFile(tempPath);
  }

  /// Pindahkan file segmen ke applicationSupportDirectory/segments/.
  /// Kembalikan path lama jika pemindahan gagal (daripada kehilangan data).
  Future<String?> _persistSegmentFile(String tempPath) async {
    try {
      final dir = await getApplicationSupportDirectory();
      final segDir = Directory(p.join(dir.path, 'segments'));
      if (!segDir.existsSync()) segDir.createSync(recursive: true);
      final dest = p.join(segDir.path, p.basename(tempPath));
      File(tempPath).renameSync(dest);
      return dest;
    } catch (_) {
      return tempPath;
    }
  }

  /// Batalkan rekaman dan hapus file-nya.
  Future<void> cancel() async {
    await _recorder.cancel();
    _recording = false;
    await _native.stopForeground();
  }

  void dispose() => _recorder.dispose();
}
