import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../event_alert_settings.dart';
import 'ble_output_commands.dart';

class ServerResponseBleEventHandler {
  ServerResponseBleEventHandler({
    required BleOutputCommands output,
    this.pulseCount = 3,
    this.pulseIntensity = 255,
    this.pulseDurationSeconds = 2,
    this.interPulseDelay = const Duration(milliseconds: 500),
    this.stateTimeout = const Duration(seconds: 5),
    this.cooldown = const Duration(seconds: 5),
    this.loadSettings,
  }) : _output = output;
  final BleOutputCommands _output;
  final int pulseCount;
  final int pulseIntensity;
  final int pulseDurationSeconds;
  final Duration interPulseDelay;
  final Duration stateTimeout;
  final Duration cooldown;
  final Future<Map<AlertEvent, AlertConfig>> Function()? loadSettings;
  Future<void> _eventQueue = Future<void>.value();
  final Set<AlertEvent> _pending = {};
  final Map<AlertEvent, DateTime> _lastCompleted = {};
  bool _disposed = false;

  @visibleForTesting
  static Set<AlertEvent> eventsFromResponse(String body) {
    final events = <AlertEvent>{};
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return events;
      final name = decoded['name_mention'] is Map
          ? decoded['name_mention'] as Map
          : decoded;
      if (name['mentioned'] == true) events.add(AlertEvent.name);
      final sound = decoded['sound_classification'];
      if (sound is Map && sound['matched'] == true) {
        final event = switch (sound['category']) {
          'phone_ring' => AlertEvent.phone,
          'fire_alarm' => AlertEvent.alarm,
          'doorbell' => AlertEvent.doorbell,
          'knocking' => AlertEvent.knocking,
          _ => null,
        };
        if (event != null) events.add(event);
      }
    } catch (_) {}
    return events;
  }

  @visibleForTesting
  static bool responseContainsNameMention(String body) =>
      eventsFromResponse(body).contains(AlertEvent.name);

  Future<void> handleSuccessfulResponse(String body) async {
    if (_disposed || !_output.isConnected) return;
    final detected = eventsFromResponse(body);
    if (detected.isEmpty) return;
    try {
      final settings =
          await (loadSettings?.call() ??
              Future.value({
                for (final event in AlertEvent.values)
                  event: AlertConfig(
                    intensity: (pulseIntensity * 100 / 255).round(),
                    duration: pulseDurationSeconds,
                    repetitions: pulseCount,
                  ),
              }));
      final queued = <Future<bool>>[];
      for (final event in detected) {
        final config = settings[event] ?? const AlertConfig();
        final last = _lastCompleted[event];
        if (!config.enabled ||
            config.intensity == 0 ||
            _pending.contains(event) ||
            (last != null && DateTime.now().difference(last) < cooldown)) {
          continue;
        }
        _pending.add(event);
        queued.add(
          _enqueue(config).whenComplete(() {
            _pending.remove(event);
            _lastCompleted[event] = DateTime.now();
          }),
        );
      }
      await Future.wait(queued);
    } catch (error, stackTrace) {
      debugPrint('Event alert failed: $error\n$stackTrace');
    }
  }

  Future<bool> testAlert(AlertConfig config) => _enqueue(config);
  Future<bool> _enqueue(AlertConfig config) {
    if (_disposed ||
        !_output.isConnected ||
        !config.enabled ||
        config.intensity == 0) {
      return Future.value(false);
    }
    // Invalidate queued alerts if the device disconnects, even if it reconnects before playback.
    var disconnected = false;
    void checkConnection() {
      if (!_output.isConnected) disconnected = true;
    }

    final connection = _output is Listenable ? _output as Listenable : null;
    connection?.addListener(checkConnection);
    final result = _eventQueue
        .then((_) async {
          if (disconnected) return false;
          for (var pulse = 0; pulse < config.repetitions; pulse++) {
            if (disconnected ||
                _disposed ||
                !_output.isConnected ||
                !await _runPulse(config)) {
              return false;
            }
            if (pulse < config.repetitions - 1) {
              await Future<void>.delayed(interPulseDelay);
            }
          }
          return true;
        })
        .catchError((Object error) {
          debugPrint('Event alert failed: $error');
          return false;
        });
    _eventQueue = result.then<void>((_) {});
    return result.whenComplete(
      () => connection?.removeListener(checkConnection),
    );
  }

  void dispose() {
    _disposed = true;
  }

  Future<bool> _runPulse(AlertConfig config) async {
    final deadline = DateTime.now().add(stateTimeout);
    while (_output.commandInProgress &&
        _output.isConnected &&
        !_disposed &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    if (_disposed || !_output.isConnected || _output.commandInProgress) {
      return false;
    }
    var sawRunning = false;
    final stopped = Completer<void>();
    final subscription = _output.hardwareStates.listen((state) {
      if (state.isRunning) {
        sawRunning = true;
      } else if (sawRunning && !stopped.isCompleted) {
        stopped.complete();
      }
    });
    try {
      if (!await _output.sendOutputCommand(
        intensity: config.pwm,
        durationSeconds: config.duration,
      )) {
        return false;
      }
      await stopped.future.timeout(
        Duration(seconds: config.duration) + stateTimeout,
      );
      return !_disposed && _output.isConnected;
    } on TimeoutException {
      debugPrint('Timed out waiting for ESP32 pulse completion.');
      return false;
    } finally {
      await subscription.cancel();
    }
  }
}
