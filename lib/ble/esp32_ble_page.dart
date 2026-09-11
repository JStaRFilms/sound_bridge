import 'dart:async';

import 'package:flutter/material.dart';

import 'esp32_ble_controller.dart';

class Esp32BlePage extends StatefulWidget {
  const Esp32BlePage({this.controller, super.key});

  final Esp32BleController? controller;

  @override
  State<Esp32BlePage> createState() => _Esp32BlePageState();
}

class _Esp32BlePageState extends State<Esp32BlePage> {
  late final Esp32BleController _controller;
  late final bool _ownsController;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? Esp32BleController();
    if (_ownsController) unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    if (_ownsController) {
      unawaited(_controller.close());
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ESP32 BLE Control')),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Connect to ${Esp32BleController.deviceName} and control its PWM intensity.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: const Color(0xFF475569)),
                          ),
                          const SizedBox(height: 24),
                          _StatusCard(controller: _controller),
                          const SizedBox(height: 20),
                          if (_controller.discoveredResult != null ||
                              _controller.isConnected)
                            _DeviceCard(controller: _controller),
                          if (_controller.discoveredResult != null ||
                              _controller.isConnected)
                            const SizedBox(height: 20),
                          _IntensityCard(controller: _controller),
                          const SizedBox(height: 20),
                          _PrimaryActions(controller: _controller),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.controller});

  final Esp32BleController controller;

  @override
  Widget build(BuildContext context) {
    final presentation = _statusPresentation(controller.status);
    final message = controller.errorMessage ?? presentation.message;

    return Card(
      elevation: 0,
      color: presentation.color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: presentation.color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_isProgressStatus(controller.status))
              SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: presentation.color,
                ),
              )
            else
              Icon(presentation.icon, color: presentation.color),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    presentation.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: presentation.color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(message, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard({required this.controller});

  final Esp32BleController controller;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFFDBEAFE),
          foregroundColor: const Color(0xFF2563EB),
          child: Icon(
            controller.isConnected
                ? Icons.bluetooth_connected_rounded
                : Icons.bluetooth_rounded,
          ),
        ),
        title: const Text(
          Esp32BleController.deviceName,
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          controller.deviceId ?? 'BLE device',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: controller.status == Esp32BleStatus.deviceFound
            ? FilledButton(
                onPressed: controller.connect,
                child: const Text('Connect'),
              )
            : null,
      ),
    );
  }
}

class _IntensityCard extends StatelessWidget {
  const _IntensityCard({required this.controller});

  final Esp32BleController controller;

  @override
  Widget build(BuildContext context) {
    final enabled = controller.canControlHardware;
    final stateColor = controller.isHardwareRunning
        ? const Color(0xFF15803D)
        : const Color(0xFF64748B);
    final stateLabel = controller.hasConfirmedState
        ? controller.isHardwareRunning
              ? 'RUNNING'
              : 'STOPPED'
        : 'UNKNOWN';
    final confirmedValues = controller.hasConfirmedState
        ? 'Confirmed: ${controller.confirmedIntensity} / 255 • ${controller.confirmedDurationSeconds}s'
        : 'Waiting for ESP32 state…';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text(
              'HARDWARE STATE',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 14),
            Text(
              stateLabel,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: stateColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              confirmedValues,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 22),
            _LabeledSlider(
              label: 'Intensity',
              valueLabel:
                  '${controller.intensity} / 255 • ${controller.intensityPercentage}%',
              value: controller.intensity.toDouble(),
              min: 0,
              max: Esp32BleController.maxIntensity.toDouble(),
              divisions: Esp32BleController.maxIntensity,
              onChanged: enabled
                  ? (value) => controller.updateIntensity(value.round())
                  : null,
            ),
            const SizedBox(height: 12),
            _LabeledSlider(
              label: 'Duration',
              valueLabel: '${controller.durationSeconds}s',
              value: controller.durationSeconds.toDouble(),
              min: 1,
              max: Esp32BleController.maxDurationSeconds.toDouble(),
              divisions: Esp32BleController.maxDurationSeconds - 1,
              onChanged: enabled
                  ? (value) => controller.updateDuration(value.round())
                  : null,
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: enabled ? controller.startOutput : null,
                    icon: controller.commandInProgress
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: enabled ? controller.stopOutput : null,
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabeledSlider extends StatelessWidget {
  const _LabeledSlider({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(valueLabel),
          ],
        ),
        Slider(
          min: min,
          max: max,
          divisions: divisions,
          value: value,
          label: valueLabel,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions({required this.controller});

  final Esp32BleController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.isConnected) {
      return OutlinedButton.icon(
        onPressed: controller.commandInProgress ? null : controller.disconnect,
        icon: const Icon(Icons.bluetooth_disabled_rounded),
        label: const Text('Disconnect'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFB91C1C),
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (controller.isScanning) {
      return OutlinedButton.icon(
        onPressed: controller.stopScan,
        icon: const Icon(Icons.stop_rounded),
        label: const Text('Cancel Scan'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }

    if (controller.status == Esp32BleStatus.connecting ||
        controller.status == Esp32BleStatus.initializing ||
        controller.status == Esp32BleStatus.bluetoothUnsupported) {
      return const SizedBox.shrink();
    }

    if (controller.status == Esp32BleStatus.bluetoothDisabled) {
      return FilledButton.icon(
        onPressed: controller.requestBluetoothOn,
        icon: const Icon(Icons.bluetooth_rounded),
        label: const Text('Turn On Bluetooth'),
        style: _primaryStyle(),
      );
    }

    if (controller.status == Esp32BleStatus.permissionDenied &&
        controller.permissionPermanentlyDenied) {
      return FilledButton.icon(
        onPressed: controller.openSettings,
        icon: const Icon(Icons.settings_rounded),
        label: const Text('Open App Settings'),
        style: _primaryStyle(),
      );
    }

    if (controller.status == Esp32BleStatus.disconnected &&
        controller.deviceId != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            onPressed: controller.reconnect,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reconnect'),
            style: _primaryStyle(),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: controller.scan,
            icon: const Icon(Icons.bluetooth_searching_rounded),
            label: const Text('Scan Again'),
          ),
        ],
      );
    }

    if (controller.status == Esp32BleStatus.deviceFound) {
      return const SizedBox.shrink();
    }

    return FilledButton.icon(
      onPressed: controller.scan,
      icon: const Icon(Icons.bluetooth_searching_rounded),
      label: Text(
        controller.status == Esp32BleStatus.ready
            ? 'Scan for ESP32'
            : 'Retry Scan',
      ),
      style: _primaryStyle(),
    );
  }

  ButtonStyle _primaryStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

bool _isProgressStatus(Esp32BleStatus status) {
  return status == Esp32BleStatus.initializing ||
      status == Esp32BleStatus.scanning ||
      status == Esp32BleStatus.connecting;
}

_StatusPresentation _statusPresentation(Esp32BleStatus status) {
  return switch (status) {
    Esp32BleStatus.initializing => const _StatusPresentation(
      'Checking Bluetooth',
      'Checking Bluetooth availability…',
      Icons.bluetooth_searching_rounded,
      Color(0xFF2563EB),
    ),
    Esp32BleStatus.ready => const _StatusPresentation(
      'Ready to scan',
      'Bluetooth is on. Start a scan to find the ESP32.',
      Icons.bluetooth_rounded,
      Color(0xFF2563EB),
    ),
    Esp32BleStatus.scanning => const _StatusPresentation(
      'Scanning',
      'Looking for ESP32-D4-BLE nearby…',
      Icons.bluetooth_searching_rounded,
      Color(0xFF2563EB),
    ),
    Esp32BleStatus.deviceFound => const _StatusPresentation(
      'Device found',
      'ESP32-D4-BLE is ready to connect.',
      Icons.bluetooth_rounded,
      Color(0xFF2563EB),
    ),
    Esp32BleStatus.connecting => const _StatusPresentation(
      'Connecting',
      'Connecting and discovering ESP32 services…',
      Icons.bluetooth_connected_rounded,
      Color(0xFF2563EB),
    ),
    Esp32BleStatus.connected => const _StatusPresentation(
      'Connected',
      'ESP32 PWM intensity control is ready.',
      Icons.check_circle_rounded,
      Color(0xFF15803D),
    ),
    Esp32BleStatus.disconnected => const _StatusPresentation(
      'Disconnected',
      'The ESP32 is not connected.',
      Icons.bluetooth_disabled_rounded,
      Color(0xFFB45309),
    ),
    Esp32BleStatus.bluetoothUnsupported => const _StatusPresentation(
      'BLE unavailable',
      'Bluetooth Low Energy is unavailable on this device.',
      Icons.error_outline_rounded,
      Color(0xFFB91C1C),
    ),
    Esp32BleStatus.bluetoothDisabled => const _StatusPresentation(
      'Bluetooth is off',
      'Turn on Bluetooth to continue.',
      Icons.bluetooth_disabled_rounded,
      Color(0xFFB45309),
    ),
    Esp32BleStatus.permissionDenied => const _StatusPresentation(
      'Permission required',
      'Allow Bluetooth access to find the ESP32.',
      Icons.lock_outline_rounded,
      Color(0xFFB91C1C),
    ),
    Esp32BleStatus.error => const _StatusPresentation(
      'Something went wrong',
      'Try the operation again.',
      Icons.error_outline_rounded,
      Color(0xFFB91C1C),
    ),
  };
}

class _StatusPresentation {
  const _StatusPresentation(this.label, this.message, this.icon, this.color);

  final String label;
  final String message;
  final IconData icon;
  final Color color;
}
