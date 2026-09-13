import 'package:flutter/material.dart';
import 'ble/esp32_ble_controller.dart';
import 'ble/server_response_ble_event_handler.dart';
import 'event_alert_settings.dart';

class EventAlertsPage extends StatefulWidget {
  const EventAlertsPage({
    required this.controller,
    required this.handler,
    super.key,
  });
  final Esp32BleController controller;
  final ServerResponseBleEventHandler handler;
  @override
  State<EventAlertsPage> createState() => _EventAlertsPageState();
}

class _EventAlertsPageState extends State<EventAlertsPage> {
  Map<AlertEvent, AlertConfig>? _settings;
  bool _saving = false;
  bool _testing = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await EventAlertSettings.load();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not load alerts. Reopen this page to retry.',
        );
      }
    }
  }

  void _update(
    AlertEvent event, {
    bool? enabled,
    int? intensity,
    int? duration,
    int? repetitions,
  }) {
    final old = _settings![event]!;
    setState(
      () => _settings![event] = AlertConfig(
        enabled: enabled ?? old.enabled,
        intensity: intensity ?? old.intensity,
        duration: duration ?? old.duration,
        repetitions: repetitions ?? old.repetitions,
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await EventAlertSettings.save(_settings!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Event alerts saved.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not save alerts. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _test(AlertEvent event) async {
    setState(() => _testing = true);
    final completed = await widget.handler.testAlert(_settings![event]!);
    if (!mounted) return;
    setState(() => _testing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          completed
              ? 'Test alert finished.'
              : 'Alert could not finish. Check the ESP32 connection.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Event alerts')),
    body: _settings == null
        ? Center(
            child: _error == null
                ? const CircularProgressIndicator()
                : Text(_error!),
          )
        : AnimatedBuilder(
            animation: widget.controller,
            builder: (context, _) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Choose how your ESP32 alerts you for each detection. Save your changes when finished.',
                ),
                if (!widget.controller.isConnected)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Connect the ESP32 in Settings to test alerts.',
                    ),
                  ),
                for (final event in AlertEvent.values) _card(event),
                const Text(
                  'Alerts play in sequence. Repeated detections are suppressed while an alert is pending and for 5 seconds after it finishes. Disconnected alerts are skipped.',
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving || _testing ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save alerts'),
                ),
              ],
            ),
          ),
  );
  Widget _card(AlertEvent event) {
    final config = _settings![event]!;
    final editable = config.enabled && !_saving && !_testing;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(event.label),
              value: config.enabled,
              onChanged: _saving || _testing
                  ? null
                  : (value) => _update(event, enabled: value),
            ),
            Text('Intensity: ${config.intensity}%'),
            Slider(
              value: config.intensity.toDouble(),
              max: 100,
              divisions: 100,
              label: '${config.intensity}%',
              onChanged: editable
                  ? (value) => _update(event, intensity: value.round())
                  : null,
            ),
            Text('Duration per pulse: ${config.duration} seconds'),
            Slider(
              value: config.duration.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${config.duration}s',
              onChanged: editable
                  ? (value) => _update(event, duration: value.round())
                  : null,
            ),
            Text('Repetitions: ${config.repetitions}'),
            Slider(
              value: config.repetitions.toDouble(),
              min: 1,
              max: 5,
              divisions: 4,
              label: '${config.repetitions}',
              onChanged: editable
                  ? (value) => _update(event, repetitions: value.round())
                  : null,
            ),
            OutlinedButton.icon(
              onPressed:
                  editable &&
                      config.intensity > 0 &&
                      widget.controller.isConnected
                  ? () => _test(event)
                  : null,
              icon: const Icon(Icons.vibration),
              label: const Text('Test alert'),
            ),
          ],
        ),
      ),
    );
  }
}
