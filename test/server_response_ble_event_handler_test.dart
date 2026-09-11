import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sound_bridge/ble/ble_output_commands.dart';
import 'package:sound_bridge/ble/server_response_ble_event_handler.dart';

void main() {
  group('ServerResponseBleEventHandler', () {
    test('detects only successful name mention payloads', () {
      expect(
        ServerResponseBleEventHandler.responseContainsNameMention(
          '{"name_mention":{"mentioned":true,"target_name":"Ada"}}',
        ),
        isTrue,
      );
      expect(
        ServerResponseBleEventHandler.responseContainsNameMention(
          '{"name_mention":{"mentioned":false,"target_name":"Ada"}}',
        ),
        isFalse,
      );
      expect(
        ServerResponseBleEventHandler.responseContainsNameMention('invalid'),
        isFalse,
      );
    });

    test('sends three 255 intensity two-second pulses', () async {
      final output = _FakeBleOutput();
      final handler = ServerResponseBleEventHandler(
        output: output,
        interPulseDelay: const Duration(milliseconds: 1),
        stateTimeout: const Duration(milliseconds: 100),
      );

      await handler.handleSuccessfulResponse(
        '{"name_mention":{"mentioned":true}}',
      );

      expect(output.commands, [
        [255, 2],
        [255, 2],
        [255, 2],
      ]);

      handler.dispose();
      await output.dispose();
    });

    test('does nothing when no name was mentioned', () async {
      final output = _FakeBleOutput();
      final handler = ServerResponseBleEventHandler(output: output);

      await handler.handleSuccessfulResponse(
        '{"name_mention":{"mentioned":false}}',
      );

      expect(output.commands, isEmpty);

      handler.dispose();
      await output.dispose();
    });
  });
}

class _FakeBleOutput implements BleOutputCommands {
  final StreamController<PwmHardwareState> _states =
      StreamController<PwmHardwareState>.broadcast();

  final List<List<int>> commands = [];

  @override
  bool isConnected = true;

  @override
  bool commandInProgress = false;

  @override
  Stream<PwmHardwareState> get hardwareStates => _states.stream;

  @override
  Future<bool> sendOutputCommand({
    required int intensity,
    required int durationSeconds,
  }) async {
    commandInProgress = true;
    commands.add([intensity, durationSeconds]);
    _states.add(
      PwmHardwareState(intensity: intensity, durationSeconds: durationSeconds),
    );
    _states.add(const PwmHardwareState(intensity: 0, durationSeconds: 0));
    commandInProgress = false;
    return true;
  }

  Future<void> dispose() => _states.close();
}
