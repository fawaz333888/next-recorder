import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:next_recorder/main.dart';
import 'package:next_recorder/services/native_service.dart';
import 'package:next_recorder/services/recorder_service.dart';
import 'package:next_recorder/state/recording_notifier.dart';

void main() {
  testWidgets('Home screen renders record button', (WidgetTester tester) async {
    final notifier = RecordingNotifier(RecorderService(), NativeService());
    await tester.pumpWidget(NextRecorderApp(notifier: notifier));

    expect(find.text('Next Recorder'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
  });
}
