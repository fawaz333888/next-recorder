package com.nextrecorder.next_recorder

import android.content.ContentValues
import android.content.Intent
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.MediaStore
import android.util.Log
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer

class MainActivity : FlutterActivity() {
    private val channel = "next_recorder/native"
    private val TAG = "NextRecorderNative"
    private var methodChannel: MethodChannel? = null

    /// Stop dari notifikasi diterima sebelum Flutter engine siap -> antrikan.
    private var pendingStop = false

    override fun onCreate(savedInstanceState: Bundle?) {
        if (intent?.getBooleanExtra(RecordingService.EXTRA_STOP_SEGMENT, false) == true) {
            pendingStop = true
        }
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra(RecordingService.EXTRA_STOP_SEGMENT, false)) {
            methodChannel?.invokeMethod("stopSegment", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "merge" -> {
                    val paths = call.argument<List<String>>("paths") ?: emptyList()
                    val outPath = call.argument<String>("outPath")
                    if (outPath == null) {
                        result.error("ARG", "outPath is null", null)
                        return@setMethodCallHandler
                    }
                    val ok = mergeSegments(paths, outPath)
                    if (ok) result.success(true)
                    else result.error("MERGE", "Failed to merge segments", null)
                }

                "saveToMediaStore" -> {
                    val src = call.argument<String>("src")
                    val name = call.argument<String>("name")
                    if (src == null || name == null) {
                        result.error("ARG", "src or name is null", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val saved = saveToMediaStore(src, name)
                        result.success(saved)
                    } catch (e: Exception) {
                        result.error("SAVE", e.message, null)
                    }
                }

                "openFile" -> {
                    val path = call.argument<String>("path")
                    result.success(openFile(path))
                }

                "shareFile" -> {
                    val path = call.argument<String>("path")
                    result.success(shareFile(path))
                }

                "fgsStart" -> {
                    val text = call.argument<String>("text") ?: "Merekam…"
                    val intent = Intent(this, RecordingService::class.java)
                        .setAction(RecordingService.ACTION_START)
                        .putExtra(RecordingService.EXTRA_TEXT, text)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(true)
                }

                "fgsUpdate" -> {
                    val text = call.argument<String>("text") ?: return@setMethodCallHandler
                    val intent = Intent(this, RecordingService::class.java)
                        .setAction(RecordingService.ACTION_UPDATE)
                        .putExtra(RecordingService.EXTRA_TEXT, text)
                    startService(intent)
                    result.success(true)
                }

                "fgsStop" -> {
                    val intent = Intent(this, RecordingService::class.java)
                        .setAction(RecordingService.ACTION_STOP)
                    startService(intent)
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }

        // Stop dari notifikasi yang datang sebelum engine siap.
        if (pendingStop) {
            pendingStop = false
            methodChannel?.invokeMethod("stopSegment", null)
        }
    }
    /// Gabungkan list file segmen .m4a menjadi satu file .m4a.
    /// Pakai MediaMuxer + MediaExtractor, tanpa re-encode (cepat & hemat CPU).
    /// Semua sample ditulis ke SATU track audio (config AAC identik karena
    /// RecordConfig sama), supaya player memutar semua segmen berurutan.
    private fun mergeSegments(paths: List<String>, outPath: String): Boolean {
        if (paths.isEmpty()) return false

        val outFile = File(outPath)
        outFile.parentFile?.mkdirs()

        var muxer: MediaMuxer? = null
        val extractors = mutableListOf<MediaExtractor>()

        try {
            muxer = MediaMuxer(outPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)

            val buffer = ByteBuffer.allocateDirect(512 * 1024)
            val info = MediaCodec.BufferInfo()
            var offsetUs = 0L
            var lastPts = -1L
            var dstTrack = -1
            var totalSamples = 0

            for ((index, p) in paths.withIndex()) {
                val extractor = MediaExtractor()
                extractor.setDataSource(p)
                extractors.add(extractor)

                var audioIdx = -1
                for (i in 0 until extractor.trackCount) {
                    val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: continue
                    if (mime.startsWith("audio/")) {
                        audioIdx = i
                        break
                    }
                }
                if (audioIdx < 0) {
                    Log.w(TAG, "Segmen ${index + 1}: tidak ada track audio, skip")
                    continue
                }

                extractor.selectTrack(audioIdx)

                // Track muxer ditambahkan sekali saja, dari segmen pertama
                // yang memiliki audio.
                if (dstTrack < 0) {
                    dstTrack = muxer.addTrack(extractor.getTrackFormat(audioIdx))
                    muxer.start()
                }

                var segSamples = 0
                var segMaxPts = 0L
                while (true) {
                    val size = extractor.readSampleData(buffer, 0)
                    if (size < 0) break

                    // Presentation time kumulatif + paksa monotonic
                    // (MediaMuxer menolak pts yang mundur).
                    var pts = extractor.sampleTime + offsetUs
                    if (pts <= lastPts) pts = lastPts + 1

                    info.offset = 0
                    info.size = size
                    // Hanya flag key frame; buang flag codec config kalau ada.
                    info.flags = extractor.sampleFlags and MediaCodec.BUFFER_FLAG_KEY_FRAME
                    info.presentationTimeUs = pts

                    muxer.writeSampleData(dstTrack, buffer, info)

                    lastPts = pts
                    segSamples++
                    if (extractor.sampleTime > segMaxPts) segMaxPts = extractor.sampleTime
                    extractor.advance()
                }

                Log.d(TAG, "Segmen ${index + 1}: $segSamples sample, maxPts=${segMaxPts}us, offset=${offsetUs}us")
                totalSamples += segSamples
                // Jeda kecil antar segmen (50ms) supaya tidak menempel.
                offsetUs += segMaxPts + 50_000
            }

            if (dstTrack < 0) {
                Log.e(TAG, "Tidak ada segmen dengan track audio, merge dibatalkan")
                return false
            }

            Log.d(TAG, "Merge selesai: $totalSamples sample")
            muxer.stop()
            return true
        } catch (e: Exception) {
            Log.e(TAG, "Merge gagal", e)
            return false
        } finally {
            try { muxer?.release() } catch (_: Exception) {}
            extractors.forEach { e -> try { e.release() } catch (_: Exception) {} }
        }
    }

    /// Simpan file ke MediaStore (Music/NextRecorder) di API 29+,
    /// atau langsung ke public Music dir di API < 29.
    /// Kembalikan uri content:// atau path absolut.
    private fun saveToMediaStore(srcPath: String, displayName: String): String? {
        val src = File(srcPath)
        if (!src.exists()) return null

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = contentResolver
            val values = ContentValues().apply {
                put(MediaStore.Audio.Media.DISPLAY_NAME, displayName)
                put(MediaStore.Audio.Media.MIME_TYPE, "audio/mp4")
                put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/NextRecorder")
                put(MediaStore.Audio.Media.IS_PENDING, 1)
            }

            val uri = resolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                ?: return null

            resolver.openOutputStream(uri)?.use { out ->
                FileInputStream(src).use { input -> input.copyTo(out) }
            } ?: return null

            val updateValues = ContentValues().apply {
                put(MediaStore.Audio.Media.IS_PENDING, 0)
            }
            resolver.update(uri, updateValues, null, null)

            uri.toString()
        } else {
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "NextRecorder")
            if (!dir.exists()) dir.mkdirs()
            val dest = File(dir, displayName)
            FileInputStream(src).use { input ->
                dest.outputStream().use { out -> input.copyTo(out) }
            }
            dest.absolutePath
        }
    }

    private fun uriForPath(path: String): Uri {
        return if (path.startsWith("content://")) {
            Uri.parse(path)
        } else {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", File(path))
        }
    }

    private fun openFile(path: String?): Boolean {
        if (path == null) return false
        return try {
            val uri = uriForPath(path)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "audio/mp4")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(intent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private fun shareFile(path: String?): Boolean {
        if (path == null) return false
        return try {
            val uri = uriForPath(path)
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "audio/mp4"
                putExtra(Intent.EXTRA_STREAM, uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(Intent.createChooser(intent, "Bagikan audio").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            })
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }
}
