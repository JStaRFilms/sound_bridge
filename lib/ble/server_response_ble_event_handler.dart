import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ble_output_commands.dart';

class ServerResponseBleEventHandler {
  ServerResponseBleEventHandler({
    required BleOutputCommands output,
    this.pulseCount = 3,
    this.pulseIntensity = 255,
    this.pulseDurationSeconds = 2,
    this.interPulseDelay = const Duration(milliseconds: 500),
    this.stateTimeout = const Duration(seconds: 5),
  }) : _output = output;

  final BleOutputCommands _output;
  final int pulseCount;
  final int pulseIntensity;
  final int pulseDurationSeconds;
  final Duration interPulseDelay;
  final Duration stateTimeout;

  Future<void> _eventQueue = Future<void>.value();
  bool _disposed = false;

  @visibleForTesting
  static bool responseContainsNameMention(String responseBody) {
    try {
      final decoded = jsonDecode(responseBody);
      if (decoded is! Map<String, dynamic>) return false;

      final nested = decoded['name_mention'];
      final namePayload = nested is Map<String, dynamic> ? nested : decoded;
      return namePayload['mentioned'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> handleSuccessfulResponse(String responseBody) async {
    if (_disposed || !responseContainsNameMention(responseBody)) return;

    final previousEvent = _eventQueue;
    final eventCompleter = Completer<void>();
    _eventQueue = eventCompleter.future;

    await previousEvent;
    try {
      await _runNameMentionSequence();
    } catch (error, stackTrace) {
      debugPrint('Name mention BLE event failed: $error\n$stackTrace');
    } finally {
      if (!eventCompleter.isCompleted) eventCompleter.complete();
    }
  }

  void dispose() {
    _disposed = true;
  }

  Future<void> _runNameMentionSequence() async {
    for (var pulse = 0; pulse < pulseCount; pulse++) {
      if (_disposed || !_output.isConnected) return;

      final completed = await _runPulse();
      if (!completed) return;

      if (pulse < pulseCount - 1) {
        await Future<void>.delayed(interPulseDelay);
      }
    }
  }

  Future<bool> _runPulse() async {
    final writeDeadline = DateTime.now().add(stateTimeout);
    while (_output.commandInProgress &&
        _output.isConnected &&
        !_disposed &&
        DateTime.now().isBefore(writeDeadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }

    if (_disposed || !_output.isConnected || _output.commandInProgress) {
      return false;
    }

    var sawRunningState = false;
    final stoppedCompleter = Completer<void>();
    final stateSubscription = _output.hardwareStates.listen((state) {
      if (state.isRunning) {
        sawRunningState = true;
      } else if (sawRunningState && !stoppedCompleter.isCompleted) {
        stoppedCompleter.complete();
      }
    });

    try {
      final sent = await _output.sendOutputCommand(
        intensity: pulseIntensity,
        durationSeconds: pulseDurationSeconds,
      );
      if (!sent) return false;

      try {
        await stoppedCompleter.future.timeout(stateTimeout);
      } on TimeoutException {
        debugPrint(
          'Timed out waiting for the ESP32 pulse completion notification.',
        );
      }
      return !_disposed && _output.isConnected;
    } finally {
      await stateSubscription.cancel();
    }
  }
}
