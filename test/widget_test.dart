import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sound_bridge/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('Dashboard shows recording and upload controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    expect(find.text('Sound Bridge'), findsOneWidget);
    expect(find.text('Listen'), findsOneWidget);
    expect(find.text('Send Audio'), findsOneWidget);
    expect(find.text('Play Recording'), findsOneWidget);
    expect(find.text('Test Vibration'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(
      find.text('Tap Listen to record a short audio clip.'),
      findsOneWidget,
    );
  });

  testWidgets('Vibration tester opens with configurable controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    await tester.ensureVisible(find.text('Test Vibration'));
    await tester.tap(find.text('Test Vibration'));
    await tester.pumpAndSettle();

    expect(find.text('Vibration'), findsOneWidget);
    expect(find.text('Length'), findsOneWidget);
    expect(find.text('Intensity'), findsOneWidget);
    expect(find.text('Vibrate'), findsOneWidget);
  });

  testWidgets('Settings sheet saves an API endpoint', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(EditableText),
      'http://192.168.1.10:8000/audio',
    );
    await tester.tap(find.text('Save Endpoint'));
    await tester.pumpAndSettle();

    expect(
      find.text('Endpoint: http://192.168.1.10:8000/audio'),
      findsOneWidget,
    );
  });

  testWidgets('Send Audio starts disabled', (WidgetTester tester) async {
    await tester.pumpWidget(const SoundBridgeApp());

    await tester.tap(find.text('Send Audio'));
    await tester.pump();

    expect(
      find.text('Tap Listen to record a short audio clip.'),
      findsOneWidget,
    );
  });
}
