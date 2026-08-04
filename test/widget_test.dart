import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:sound_bridge/main.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    await preferences.clear();
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
    expect(find.text('Target: not set'), findsOneWidget);
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

  testWidgets('Settings sheet saves endpoint and target name', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);
    expect(textFields, findsNWidgets(2));

    await tester.enterText(
      textFields.at(0),
      'http://192.168.1.10:8000/v1/audio/analyze',
    );
    await tester.enterText(textFields.at(1), 'john');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(
      find.text('Endpoint: http://192.168.1.10:8000/v1/audio/analyze'),
      findsOneWidget,
    );
    expect(find.text('Target: john'), findsOneWidget);
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

  testWidgets('Settings can save endpoint without target name', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final textFields = find.byType(TextField);

    await tester.enterText(
      textFields.at(0),
      'http://127.0.0.1:8000/v1/audio/analyze',
    );
    await tester.enterText(textFields.at(1), '');
    await tester.tap(find.text('Save Settings'));
    await tester.pumpAndSettle();

    expect(
      find.text('Endpoint: http://127.0.0.1:8000/v1/audio/analyze'),
      findsOneWidget,
    );
    expect(find.text('Target: not set'), findsOneWidget);
  });
}
