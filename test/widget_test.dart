import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:next_recorder/main.dart';

void main() {
  testWidgets('Home screen renders record button', (WidgetTester tester) async {
    await tester.pumpWidget(const NextRecorderApp());

    expect(find.text('Next Recorder'), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect(find.text('Simpan'), findsOneWidget);
  });
}
