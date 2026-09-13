import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sound_bridge/main.dart';
import 'package:sound_bridge/event_alert_settings.dart';

void main() {
  testWidgets('Settings opens event alerts and saves edited duration', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const SoundBridgeApp());
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Event alerts'));
    await tester.tap(find.text('Event alerts'));
    await tester.pumpAndSettle();
    expect(find.text('Name detected'), findsOneWidget);
    final duration = find
        .byWidgetPredicate((widget) => widget is Slider && widget.max == 5)
        .first;
    final slider = tester.widget<Slider>(duration);
    slider.onChanged!(4);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text('Save alerts'),
      400,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Save alerts'));
    await tester.pumpAndSettle();
    expect((await EventAlertSettings.load())[AlertEvent.name]!.duration, 4);
    expect(find.text('Event alerts saved.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
