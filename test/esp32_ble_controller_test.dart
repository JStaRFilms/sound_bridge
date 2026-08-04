import 'package:flutter_test/flutter_test.dart';
import 'package:sound_bridge/ble/esp32_ble_controller.dart';

void main() {
  group('ESP32 PWM protocol', () {
    test('control payload is exactly one raw byte', () {
      for (final intensity in [0, 1, 128, 254, 255]) {
        final payload = Esp32BleController.controlPayloadFor(intensity);

        expect(payload, hasLength(1));
        expect(payload.single, intensity);
      }
    });

    test('state is decoded from the first raw byte', () {
      expect(Esp32BleController.intensityFromState([]), isNull);
      expect(Esp32BleController.intensityFromState([0]), 0);
      expect(Esp32BleController.intensityFromState([128]), 128);
      expect(Esp32BleController.intensityFromState([255]), 255);
    });

    test('percentage uses the full 0 to 255 range', () {
      expect(Esp32BleController.percentageFor(0), 0);
      expect(Esp32BleController.percentageFor(128), 50);
      expect(Esp32BleController.percentageFor(255), 100);
    });
  });
}
