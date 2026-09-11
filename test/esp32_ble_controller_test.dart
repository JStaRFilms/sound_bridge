import 'package:flutter_test/flutter_test.dart';
import 'package:sound_bridge/ble/esp32_ble_controller.dart';

void main() {
  group('ESP32 PWM protocol', () {
    test('start payload contains intensity and duration bytes', () {
      final payload = Esp32BleController.controlPayloadFor(128, 12);

      expect(payload, [128, 12]);
      expect(payload, hasLength(2));
    });

    test('zero or missing duration defaults to five seconds', () {
      expect(Esp32BleController.controlPayloadFor(128), [128, 5]);
      expect(Esp32BleController.controlPayloadFor(128, 0), [128, 5]);
    });

    test('stop payload is exactly zero intensity and duration', () {
      expect(Esp32BleController.controlPayloadFor(0, 0), [0, 0]);
    });

    test('state requires and decodes two raw bytes', () {
      expect(Esp32BleController.stateFromNotification([]), isNull);
      expect(Esp32BleController.stateFromNotification([128]), isNull);

      final running = Esp32BleController.stateFromNotification([128, 12]);
      expect(running?.intensity, 128);
      expect(running?.durationSeconds, 12);
      expect(running?.isRunning, isTrue);

      final stopped = Esp32BleController.stateFromNotification([0, 0]);
      expect(stopped?.isRunning, isFalse);
    });

    test('percentage uses the full 0 to 255 range', () {
      expect(Esp32BleController.percentageFor(0), 0);
      expect(Esp32BleController.percentageFor(128), 50);
      expect(Esp32BleController.percentageFor(255), 100);
    });
  });
}
