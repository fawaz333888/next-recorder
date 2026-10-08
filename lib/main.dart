import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/native_service.dart';
import 'services/recorder_service.dart';
import 'state/playback_notifier.dart';
import 'state/recording_notifier.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifier = RecordingNotifier(RecorderService(), NativeService());
  // Tombol Stop di notifikasi foreground service -> akhiri segmen.
  NativeService().setStopSegmentHandler(() => notifier.stopSegment());
  // Pulihkan segmen dari sesi sebelumnya (kalau OS membunuh app).
  await notifier.loadSession();

  runApp(NextRecorderApp(notifier: notifier));
}

class NextRecorderApp extends StatelessWidget {
  const NextRecorderApp({super.key, required this.notifier});

  final RecordingNotifier notifier;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: notifier),
        ChangeNotifierProvider(create: (_) => PlaybackNotifier()),
      ],
      child: MaterialApp(
        title: 'Next Recorder',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.indigo,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
