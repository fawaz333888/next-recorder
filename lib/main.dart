import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/home_screen.dart';
import 'services/native_service.dart';
import 'services/recorder_service.dart';
import 'state/recording_notifier.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NextRecorderApp());
}

class NextRecorderApp extends StatelessWidget {
  const NextRecorderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RecordingNotifier(RecorderService(), NativeService()),
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
