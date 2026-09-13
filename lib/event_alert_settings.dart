import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

enum AlertEvent {
  name('Name detected'),
  phone('Phone ringing detected'),
  alarm('Alarm detected'),
  doorbell('Doorbell detected'),
  knocking('Knocking detected');

  const AlertEvent(this.label);
  final String label;
}

class AlertConfig {
  const AlertConfig({
    this.enabled = true,
    this.intensity = 40,
    this.duration = 2,
    this.repetitions = 3,
  });
  final bool enabled;
  final int intensity;
  final int duration;
  final int repetitions;
  int get pwm => (intensity * 255 / 100).round();
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'intensity': intensity,
    'duration': duration,
    'repetitions': repetitions,
  };
  factory AlertConfig.fromJson(Map<String, dynamic> json) {
    int value(String key, int fallback, int min, int max) =>
        (json[key] is num ? (json[key] as num).toInt() : fallback).clamp(
          min,
          max,
        );
    return AlertConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      intensity: value('intensity', 40, 0, 100),
      duration: value('duration', 2, 1, 5),
      repetitions: value('repetitions', 3, 1, 5),
    );
  }
}

class EventAlertSettings {
  static const storageKey = 'event_alerts_v1';
  static Future<Map<AlertEvent, AlertConfig>> load() async {
    final preferences = await SharedPreferences.getInstance();
    Map<String, dynamic> data = {};
    try {
      final decoded = jsonDecode(preferences.getString(storageKey) ?? '{}');
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}
    return {
      for (final event in AlertEvent.values)
        event: data[event.name] is Map<String, dynamic>
            ? AlertConfig.fromJson(data[event.name] as Map<String, dynamic>)
            : const AlertConfig(),
    };
  }

  static Future<void> save(Map<AlertEvent, AlertConfig> settings) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(
      storageKey,
      jsonEncode({
        for (final entry in settings.entries)
          entry.key.name: entry.value.toJson(),
      }),
    );
    if (!saved) throw StateError('Could not save event alerts.');
  }
}
