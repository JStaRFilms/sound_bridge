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
    expect(find.text('ESP32 Output'), findsNothing);
    expect(find.text('ESP32 BLE Control'), findsNothing);
    expect(find.byTooltip('Settings'), findsOneWidget);
    expect(
      find.text('Tap Listen to record a short audio clip.'),
      findsOneWidget,
    );
    expect(find.text('Target: not set'), findsOneWidget);
  });

  testWidgets('triple tapping the header opens hidden ESP32 debug controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    final header = find.byKey(const Key('soundBridgeHeader'));
    await tester.tap(header);
    await tester.tap(header);
    await tester.tap(header);
    await tester.pumpAndSettle();

    expect(find.text('ESP32 Debug'), findsOneWidget);
    expect(find.text('ESP32 Output'), findsOneWidget);
    expect(find.text('ESP32 BLE Control'), findsOneWidget);

    final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
    final intensitySlider = sliders.singleWhere((slider) => slider.min == 0);
    final durationSlider = sliders.singleWhere((slider) => slider.min == 1);

    expect(intensitySlider.max, 255);
    expect(intensitySlider.divisions, 255);
    expect(intensitySlider.onChanged, isNull);
    expect(durationSlider.value, 5);
    expect(durationSlider.max, 30);
    expect(durationSlider.onChanged, isNull);
    expect(
      find.text('Connect the ESP32 from Settings to enable these controls.'),
      findsOneWidget,
    );
  });

  testWidgets('Settings provides ESP32 connection controls', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SoundBridgeApp());

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('ESP32 Bluetooth'), findsOneWidget);
    expect(find.text('Not connected'), findsOneWidget);
    expect(find.text('Scan for ESP32'), findsOneWidget);
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
