import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/segment.dart';
import '../state/playback_notifier.dart';
import '../state/recording_notifier.dart';
import '../utils/format.dart';
import 'result_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  void _showMicDenied() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Izin mikrofon diperlukan untuk merekam')),
    );
  }

  Future<void> _onHoldDown() async {
    final playback = context.read<PlaybackNotifier>();
    final recorder = context.read<RecordingNotifier>();
    await playback.stopAll();
    final ok = await recorder.startSegment();
    if (!ok && mounted) _showMicDenied();
  }

  void _onHoldUp() {
    context.read<RecordingNotifier>().stopSegment();
  }

  Future<void> _onToggleTap() async {
    final n = context.read<RecordingNotifier>();
    if (n.isRecording) {
      await n.stopSegment();
    } else {
      await context.read<PlaybackNotifier>().stopAll();
      final ok = await n.startSegment();
      if (!ok && mounted) _showMicDenied();
    }
  }

  Future<void> _onUndo() async {
    final n = context.read<RecordingNotifier>();
    final playback = context.read<PlaybackNotifier>();
    final last = n.lastSegment;
    if (last == null) return;

    // Konfirmasi untuk segmen panjang agar tidak hapus tidak sengaja.
    if (last.durationMs >= 30000) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hapus segmen terakhir?'),
          content: Text(
            '${last.label} berdurasi ${formatDuration(last.durationMs)} '
            'akan dihapus permanen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await playback.stopAll();
    await n.undo();
  }

  Future<void> _onFinish() async {
    final n = context.read<RecordingNotifier>();
    final playback = context.read<PlaybackNotifier>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Menggabungkan segmen...'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    await playback.stopAll();

    final saved = await n.finish();

    if (!mounted) return;
    Navigator.of(context).pop(); // tutup dialog loading

    if (saved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menggabungkan/menyimpan audio')),
      );
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ResultScreen(savedPath: saved),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final n = context.watch<RecordingNotifier>();
    final theme = Theme.of(context);
    final recording = n.isRecording;
    final hold = n.mode == RecordMode.hold;

    if (recording) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      if (_pulse.isAnimating) _pulse.stop();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Next Recorder'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          ValueListenableBuilder<int>(
            valueListenable: n.total,
            builder: (ctx, value, _) => Text(
              formatClock(value),
              style: theme.textTheme.displayMedium?.copyWith(
                fontWeight: FontWeight.w300,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Text('Total durasi', style: theme.textTheme.labelSmall),
          const SizedBox(height: 12),
          SegmentedButton<RecordMode>(
            segments: const [
              ButtonSegment(
                value: RecordMode.hold,
                icon: Icon(Icons.touch_app_rounded),
                label: Text('Tahan'),
              ),
              ButtonSegment(
                value: RecordMode.toggle,
                icon: Icon(Icons.fiber_manual_record_rounded),
                label: Text('Tekan'),
              ),
            ],
            selected: {n.mode},
            onSelectionChanged: (_) => n.toggleMode(),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: n.segments.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        hold
                            ? 'Belum ada segmen.\nTahan tombol rekam sambil berbicara, lepaskan untuk berhenti.'
                            : 'Belum ada segmen.\nKetuk tombol rekam untuk mulai, ketuk lagi untuk berhenti.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: n.segments.length,
                    itemBuilder: (ctx, i) {
                      final seg = n.segments[n.segments.length - 1 - i];
                      return _SegmentTile(segment: seg, enabled: !recording);
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: n.elapsed,
                builder: (ctx, value, _) => Text(
                  recording ? formatDuration(value) : ' ',
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: Colors.red,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _SideButton(
                    icon: Icons.undo_rounded,
                    label: 'Undo',
                    color: theme.colorScheme.error,
                    onTap: n.canUndo ? _onUndo : null,
                  ),
                  _RecordButton(
                    pulse: _pulse,
                    recording: recording,
                    hold: hold,
                    onHoldDown: _onHoldDown,
                    onHoldUp: _onHoldUp,
                    onToggleTap: _onToggleTap,
                  ),
                  _SideButton(
                    icon: Icons.check_rounded,
                    label: 'Simpan',
                    color: theme.colorScheme.primary,
                    onTap: n.canFinish ? _onFinish : null,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({required this.segment, required this.enabled});

  final Segment segment;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = context.watch<PlaybackNotifier>().isPlaying(segment.id);

    return Card(
      child: ListTile(
        leading: CircleAvatar(child: Text('${segment.id}')),
        title: Text(segment.label),
        subtitle: Text(clockTime(segment.createdAt)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: enabled
                  ? () => context.read<PlaybackNotifier>().toggle(segment)
                  : null,
              icon: Icon(
                playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
              ),
              tooltip: playing ? 'Jeda' : 'Putar segmen',
            ),
            Text(
              formatDuration(segment.durationMs),
              style: theme.textTheme.titleMedium?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: enabled ? () => onTap!() : null,
            icon: Icon(icon),
            iconSize: 32,
            color: color,
          ),
          Text(
            label,
            style: TextStyle(
              color: enabled ? null : Theme.of(context).disabledColor,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.pulse,
    required this.recording,
    required this.hold,
    required this.onHoldDown,
    required this.onHoldUp,
    required this.onToggleTap,
  });

  final AnimationController pulse;
  final bool recording;
  final bool hold;
  final Future<void> Function() onHoldDown;
  final void Function() onHoldUp;
  final Future<void> Function() onToggleTap;

  @override
  Widget build(BuildContext context) {
    final baseColor = recording ? Colors.red : Theme.of(context).colorScheme.primary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: hold ? (_) => onHoldDown() : null,
      onTapUp: hold ? (_) => onHoldUp() : null,
      onTapCancel: hold ? onHoldUp : null,
      onTap: hold ? null : () => onToggleTap(),
      child: AnimatedBuilder(
        animation: pulse,
        builder: (ctx, child) {
          final t = recording ? pulse.value : 0.0;
          return Stack(
            alignment: Alignment.center,
            children: [
              // Ring pulse saat recording
              Container(
                width: 96 + 28 * t,
                height: 96 + 28 * t,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.red.withValues(alpha: 0.16 * (1 - t)),
                ),
              ),
              child!,
            ],
          );
        },
        child: Container(
          width: 88,
          height: 88,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: baseColor,
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            recording ? Icons.stop_rounded : Icons.mic_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }
}
