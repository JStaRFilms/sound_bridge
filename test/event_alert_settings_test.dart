import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sound_bridge/event_alert_settings.dart';

void main() {
  test('saves and restores independent event settings', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await EventAlertSettings.load();
    settings[AlertEvent.phone] = const AlertConfig(
      enabled: false,
      intensity: 42,
      duration: 5,
      repetitions: 1,
    );
    await EventAlertSettings.save(settings);
    final restored = await EventAlertSettings.load();
    expect(restored[AlertEvent.phone]!.enabled, false);
    expect(restored[AlertEvent.phone]!.intensity, 42);
    expect(restored[AlertEvent.phone]!.duration, 5);
    expect(restored[AlertEvent.phone]!.repetitions, 1);
    expect(restored[AlertEvent.name]!.intensity, 40);
    expect(restored[AlertEvent.doorbell]!.enabled, true);
    expect(restored[AlertEvent.doorbell]!.intensity, 40);
  });
  test(
    'invalid saved values are bounded and corrupt storage uses defaults',
    () async {
      final config = AlertConfig.fromJson({
        'duration': 255,
        'intensity': -10,
        'repetitions': 20,
      });
      expect(config.duration, 5);
      expect(config.intensity, 0);
      expect(config.repetitions, 5);
      SharedPreferences.setMockInitialValues({
        EventAlertSettings.storageKey: 'invalid',
      });
      expect((await EventAlertSettings.load())[AlertEvent.name]!.duration, 2);
    },
  );
}
