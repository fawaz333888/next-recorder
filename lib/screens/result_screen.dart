import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/native_service.dart';
import '../state/recording_notifier.dart';

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key, required this.savedPath});

  final String savedPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = savedPath.split('/').last.split('%2F').last;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tersimpan'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 80,
              ),
              const SizedBox(height: 16),
              const Text(
                'Audio berhasil disimpan',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Cari di Music/NextRecorder atau di app pemutar musik.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                fileName,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ActionButton(
                    icon: Icons.play_arrow_rounded,
                    label: 'Buka',
                    onTap: () async {
                      final ok = await NativeService().openFile(savedPath);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tidak ada aplikasi untuk membuka file'),
                          ),
                        );
                      }
                    },
                  ),
                  _ActionButton(
                    icon: Icons.share_rounded,
                    label: 'Bagikan',
                    onTap: () async {
                      final ok = await NativeService().shareFile(savedPath);
                      if (!ok && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Gagal membagikan file')),
                        );
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () {
                  context.read<RecordingNotifier>().reset();
                  Navigator.of(context).popUntil((r) => r.isFirst);
                },
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24),
                  child: Text('Rekam lagi'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      child: Column(
        children: [
          IconButton.filled(
            onPressed: onTap,
            icon: Icon(icon),
            iconSize: 30,
          ),
          const SizedBox(height: 4),
          Text(label),
        ],
      ),
    );
  }
}
