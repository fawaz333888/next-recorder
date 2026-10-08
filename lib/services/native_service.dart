import 'package:flutter/services.dart';

/// Jembatan ke kode native Android (Kotlin) via MethodChannel.
/// Semua operasi on-device, tanpa jaringan.
class NativeService {
  static const _channel = MethodChannel('next_recorder/native');

  static void Function()? _onStopSegment;

  /// Handler tombol Stop di notifikasi foreground service.
  void setStopSegmentHandler(void Function()? handler) {
    _onStopSegment = handler;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'stopSegment') _onStopSegment?.call();
    });
  }

  /// Mulai foreground service (notif dengan tombol Stop).
  Future<void> startForeground(String text) =>
      _channel.invokeMethod('fgsStart', {'text': text});

  /// Update teks notifikasi (dipanggil tiap detik dari Dart).
  Future<void> updateForeground(String text) =>
      _channel.invokeMethod('fgsUpdate', {'text': text});

  /// Hentikan foreground service.
  Future<void> stopForeground() => _channel.invokeMethod('fgsStop');

  /// Gabungkan list file segmen m4a menjadi satu file m4a (MediaMuxer, no re-encode).
  Future<bool> merge(List<String> paths, String outPath) async {
    final result = await _channel.invokeMethod<bool>('merge', {
      'paths': paths,
      'outPath': outPath,
    });
    return result ?? false;
  }

  /// Simpan file ke MediaStore (Music/NextRecorder). Kembalikan uri content:// (API 29+)
  /// atau path absolut (di bawah API 29).
  Future<String?> saveToMediaStore(String srcPath, String displayName) async {
    return _channel.invokeMethod<String>('saveToMediaStore', {
      'src': srcPath,
      'name': displayName,
    });
  }

  /// Buka file dengan aplikasi eksternal.
  Future<bool> openFile(String uriOrPath) async {
    final result = await _channel.invokeMethod<bool>('openFile', {
      'path': uriOrPath,
    });
    return result ?? false;
  }

  /// Bagikan file ke aplikasi lain.
  Future<bool> shareFile(String uriOrPath) async {
    final result = await _channel.invokeMethod<bool>('shareFile', {
      'path': uriOrPath,
    });
    return result ?? false;
  }
}
