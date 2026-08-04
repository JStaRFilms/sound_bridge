import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

enum Esp32BleStatus {
  initializing,
  ready,
  scanning,
  deviceFound,
  connecting,
  connected,
  disconnected,
  bluetoothUnsupported,
  bluetoothDisabled,
  permissionDenied,
  error,
}

class Esp32BleController extends ChangeNotifier {
  static const maxIntensity = 255;
  static const _writeInterval = Duration(milliseconds: 75);
  static const deviceName = 'ESP32-D4-BLE';
  static final serviceUuid = Guid('19b10000-e8f2-537e-4f6c-d104768a1214');
  static final stateCharacteristicUuid = Guid(
    '19b10001-e8f2-537e-4f6c-d104768a1214',
  );
  static final controlCharacteristicUuid = Guid(
    '19b10002-e8f2-537e-4f6c-d104768a1214',
  );

  @visibleForTesting
  static Uint8List controlPayloadFor(int intensity) {
    RangeError.checkValueInInterval(intensity, 0, maxIntensity, 'intensity');
    return Uint8List.fromList([intensity]);
  }

  @visibleForTesting
  static int? intensityFromState(List<int> data) {
    return data.isEmpty ? null : data.first;
  }

  @visibleForTesting
  static int percentageFor(int intensity) {
    return (intensity / maxIntensity * 100).round();
  }

  Esp32BleStatus status = Esp32BleStatus.initializing;
  int intensity = 0;
  bool hasIntensity = false;
  BluetoothAdapterState adapterState = BluetoothAdapterState.unknown;
  ScanResult? discoveredResult;
  String? errorMessage;
  bool permissionPermanentlyDenied = false;
  bool commandInProgress = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _stateCharacteristic;
  BluetoothCharacteristic? _controlCharacteristic;
  StreamSubscription<BluetoothAdapterState>? _adapterSubscription;
  StreamSubscription<List<ScanResult>>? _scanResultsSubscription;
  StreamSubscription<BluetoothConnectionState>? _connectionSubscription;
  StreamSubscription<List<int>>? _stateValueSubscription;
  bool _connectInProgress = false;
  bool _userRequestedDisconnect = false;
  bool _isAdjustingIntensity = false;
  int? _pendingIntensity;
  Timer? _writeDebounce;
  DateTime? _lastWriteStartedAt;
  Completer<void>? _writeLoopCompleter;
  bool _closed = false;

  bool get isConnected => status == Esp32BleStatus.connected;
  bool get isScanning => status == Esp32BleStatus.scanning;
  bool get canAdjustIntensity => isConnected && !_userRequestedDisconnect;
  int get intensityPercentage => percentageFor(intensity);
  String? get deviceId {
    final device = _device ?? discoveredResult?.device;
    return device?.remoteId.str;
  }

  Future<void> initialize() async {
    try {
      if (!await FlutterBluePlus.isSupported) {
        _setStatus(
          Esp32BleStatus.bluetoothUnsupported,
          message: 'Bluetooth Low Energy is not supported on this device.',
        );
        return;
      }

      await _adapterSubscription?.cancel();
      _adapterSubscription = FlutterBluePlus.adapterState.listen(
        _handleAdapterState,
      );
      _handleAdapterState(FlutterBluePlus.adapterStateNow);
    } catch (error) {
      _setError('Unable to check Bluetooth: ${_describeError(error)}');
    }
  }

  Future<void> scan() async {
    if (_closed || isConnected || _connectInProgress) return;

    errorMessage = null;
    permissionPermanentlyDenied = false;

    try {
      if (!await FlutterBluePlus.isSupported) {
        _setStatus(
          Esp32BleStatus.bluetoothUnsupported,
          message: 'Bluetooth Low Energy is not supported on this device.',
        );
        return;
      }

      adapterState = FlutterBluePlus.adapterStateNow;
      if (adapterState != BluetoothAdapterState.on) {
        _setStatus(
          Esp32BleStatus.bluetoothDisabled,
          message: _adapterMessage(adapterState),
        );
        return;
      }

      if (!await _requestScanPermissions()) return;

      await stopScan(updateStatus: false);
      discoveredResult = null;
      _setStatus(Esp32BleStatus.scanning);

      _scanResultsSubscription = FlutterBluePlus.onScanResults.listen(
        _handleScanResults,
        onError: (Object error) {
          _setError('Scan failed: ${_describeError(error)}');
        },
      );

      await FlutterBluePlus.startScan(
        withServices: [serviceUuid],
        withNames: const [deviceName],
        timeout: const Duration(seconds: 12),
        androidUsesFineLocation: false,
      );

      await FlutterBluePlus.isScanning.where((scanning) => !scanning).first;
      if (!_closed && status == Esp32BleStatus.scanning) {
        _setStatus(
          Esp32BleStatus.disconnected,
          message:
              '$deviceName was not found. Make sure it is powered on and nearby.',
        );
      }
      await _cancelScanSubscription();
    } catch (error) {
      await stopScan(updateStatus: false);
      _setError('Scan failed: ${_describeError(error)}');
    }
  }

  Future<void> stopScan({bool updateStatus = true}) async {
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } catch (_) {
      // Cleanup should continue even if the native scan has already stopped.
    }
    await _cancelScanSubscription();

    if (updateStatus && isScanning) {
      _setStatus(Esp32BleStatus.ready);
    }
  }

  Future<void> connect([BluetoothDevice? selectedDevice]) async {
    if (_closed || _connectInProgress || isConnected) return;

    final device = selectedDevice ?? discoveredResult?.device ?? _device;
    if (device == null) {
      _setError('Scan for $deviceName before connecting.');
      return;
    }

    await stopScan(updateStatus: false);
    await _cancelDeviceSubscriptions(keepConnectionSubscription: false);
    _device = device;
    _connectInProgress = true;
    _userRequestedDisconnect = false;
    intensity = 0;
    hasIntensity = false;
    errorMessage = null;
    _setStatus(Esp32BleStatus.connecting);

    _connectionSubscription = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected &&
          !_connectInProgress &&
          !_userRequestedDisconnect &&
          (status == Esp32BleStatus.connected ||
              status == Esp32BleStatus.connecting)) {
        unawaited(_handleUnexpectedDisconnection());
      }
    });

    try {
      await device.connect(
        license: License.nonprofit,
        timeout: const Duration(seconds: 20),
      );

      final services = await device.discoverServices();
      final service = services.cast<BluetoothService?>().firstWhere(
        (candidate) => candidate?.uuid == serviceUuid,
        orElse: () => null,
      );
      if (service == null) {
        throw StateError('Required ESP32 service was not found.');
      }

      _stateCharacteristic = service.characteristics
          .cast<BluetoothCharacteristic?>()
          .firstWhere(
            (candidate) => candidate?.uuid == stateCharacteristicUuid,
            orElse: () => null,
          );
      _controlCharacteristic = service.characteristics
          .cast<BluetoothCharacteristic?>()
          .firstWhere(
            (candidate) => candidate?.uuid == controlCharacteristicUuid,
            orElse: () => null,
          );

      if (_stateCharacteristic == null || _controlCharacteristic == null) {
        throw StateError('Required ESP32 characteristics were not found.');
      }
      if (!_stateCharacteristic!.properties.read ||
          !_stateCharacteristic!.properties.notify) {
        throw StateError(
          'The ESP32 state characteristic does not support read and notify.',
        );
      }
      if (!_controlCharacteristic!.properties.write) {
        throw StateError(
          'The ESP32 control characteristic does not support write.',
        );
      }

      _stateValueSubscription = _stateCharacteristic!.onValueReceived.listen(
        _handleStateValue,
      );
      _handleStateValue(await _stateCharacteristic!.read());
      await _stateCharacteristic!.setNotifyValue(true);

      _connectInProgress = false;
      _setStatus(Esp32BleStatus.connected);
    } catch (error) {
      _connectInProgress = false;
      await _cancelDeviceSubscriptions(keepConnectionSubscription: false);
      try {
        await device.disconnect();
      } catch (_) {
        // Preserve the original, more useful connection error.
      }
      intensity = 0;
      hasIntensity = false;
      _setStatus(
        Esp32BleStatus.error,
        message: 'Connection failed: ${_describeError(error)}',
      );
    }
  }

  Future<void> reconnect() => connect(_device ?? discoveredResult?.device);

  void beginIntensityAdjustment() {
    if (canAdjustIntensity) _isAdjustingIntensity = true;
  }

  void updateIntensity(int value) {
    if (!canAdjustIntensity) return;

    final nextIntensity = value.clamp(0, maxIntensity).toInt();
    intensity = nextIntensity;
    hasIntensity = true;
    _pendingIntensity = nextIntensity;
    errorMessage = null;
    _notify();

    _writeDebounce?.cancel();
    _writeDebounce = Timer(
      _writeInterval,
      () => unawaited(_flushPendingIntensity()),
    );
  }

  void finishIntensityAdjustment(int value) {
    if (!canAdjustIntensity) return;

    _isAdjustingIntensity = false;
    updateIntensity(value);
    _writeDebounce?.cancel();
    unawaited(_flushPendingIntensity());
  }

  Future<void> _flushPendingIntensity() async {
    if (_writeLoopCompleter != null ||
        _closed ||
        !isConnected ||
        _controlCharacteristic == null ||
        _pendingIntensity == null) {
      return;
    }

    final completer = Completer<void>();
    _writeLoopCompleter = completer;
    commandInProgress = true;
    _notify();

    try {
      while (!_closed && isConnected && _pendingIntensity != null) {
        final lastWrite = _lastWriteStartedAt;
        if (lastWrite != null) {
          final elapsed = DateTime.now().difference(lastWrite);
          final remaining = _writeInterval - elapsed;
          if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        }

        if (_closed || !isConnected || _pendingIntensity == null) break;

        final nextIntensity = _pendingIntensity!;
        _pendingIntensity = null;
        _lastWriteStartedAt = DateTime.now();
        await _controlCharacteristic!.write(
          controlPayloadFor(nextIntensity),
          withoutResponse: false,
        );
      }
    } catch (error) {
      _pendingIntensity = null;
      errorMessage = 'PWM intensity update failed: ${_describeError(error)}';
    } finally {
      commandInProgress = false;
      _writeLoopCompleter = null;
      if (!completer.isCompleted) completer.complete();
      _notify();
    }
  }

  Future<void> disconnect() async {
    _userRequestedDisconnect = true;
    _connectInProgress = false;
    _notify();
    await stopScan(updateStatus: false);
    await _cancelPendingIntensityWrites();

    final device = _device;
    await _cancelDeviceSubscriptions(keepConnectionSubscription: false);
    if (device != null) {
      try {
        await device.disconnect();
      } catch (error) {
        errorMessage = 'Disconnect failed: ${_describeError(error)}';
      }
    }

    intensity = 0;
    hasIntensity = false;
    _setStatus(
      Esp32BleStatus.disconnected,
      message: errorMessage ?? 'Disconnected from $deviceName.',
    );
  }

  Future<void> requestBluetoothOn() async {
    errorMessage = null;
    if (!kIsWeb && Platform.isAndroid) {
      try {
        await FlutterBluePlus.turnOn();
      } catch (error) {
        _setStatus(
          Esp32BleStatus.bluetoothDisabled,
          message: 'Turn on Bluetooth in system settings, then try again.',
        );
      }
    } else {
      _setStatus(
        Esp32BleStatus.bluetoothDisabled,
        message: 'Turn on Bluetooth in system settings, then try again.',
      );
    }
  }

  Future<void> openSettings() => openAppSettings();

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _userRequestedDisconnect = true;
    await stopScan(updateStatus: false);
    await _cancelPendingIntensityWrites();
    await _adapterSubscription?.cancel();
    _adapterSubscription = null;
    await _cancelDeviceSubscriptions(keepConnectionSubscription: false);
    try {
      await _device?.disconnect();
    } catch (_) {
      // The device may already have disconnected while the screen was closing.
    }
  }

  Future<bool> _requestScanPermissions() async {
    if (kIsWeb || !Platform.isAndroid) return true;

    final sdk = (await DeviceInfoPlugin().androidInfo).version.sdkInt;
    final permissions = sdk >= 31
        ? <Permission>[Permission.bluetoothScan, Permission.bluetoothConnect]
        : <Permission>[Permission.locationWhenInUse];
    final results = await permissions.request();
    final denied = results.values.where((result) => !result.isGranted).toList();

    if (denied.isEmpty) return true;

    permissionPermanentlyDenied = denied.any(
      (result) => result.isPermanentlyDenied || result.isRestricted,
    );
    _setStatus(
      Esp32BleStatus.permissionDenied,
      message: permissionPermanentlyDenied
          ? 'Bluetooth permission is blocked. Open app settings to allow Nearby devices access.'
          : sdk >= 31
          ? 'Nearby devices permission is required to find and connect to the ESP32.'
          : 'Location permission is required to scan for BLE devices on this Android version.',
    );
    return false;
  }

  void _handleAdapterState(BluetoothAdapterState state) {
    if (_closed) return;
    adapterState = state;

    if (state == BluetoothAdapterState.on) {
      if (!isConnected && !_connectInProgress && !isScanning) {
        _setStatus(Esp32BleStatus.ready);
      } else {
        _notify();
      }
      return;
    }

    if (state == BluetoothAdapterState.unauthorized) {
      permissionPermanentlyDenied = true;
      _setStatus(
        Esp32BleStatus.permissionDenied,
        message:
            'Bluetooth access is blocked. Open app settings to allow access.',
      );
      return;
    }

    if (state == BluetoothAdapterState.unavailable) {
      _setStatus(
        Esp32BleStatus.bluetoothUnsupported,
        message: 'Bluetooth Low Energy is unavailable on this device.',
      );
      return;
    }

    if (state == BluetoothAdapterState.off ||
        state == BluetoothAdapterState.turningOff) {
      unawaited(_cleanUpAfterBluetoothTurnsOff());
      _setStatus(
        Esp32BleStatus.bluetoothDisabled,
        message: 'Bluetooth is turned off. Turn it on to find the ESP32.',
      );
      return;
    }

    status = Esp32BleStatus.initializing;
    errorMessage = 'Checking Bluetooth status…';
    _notify();
  }

  Future<void> _cleanUpAfterBluetoothTurnsOff() async {
    await stopScan(updateStatus: false);
    await _cancelPendingIntensityWrites();
    await _cancelDeviceSubscriptions(keepConnectionSubscription: false);
    intensity = 0;
    hasIntensity = false;
    _notify();
  }

  void _handleScanResults(List<ScanResult> results) {
    if (_closed || !isScanning) return;

    for (final result in results) {
      final advertisedName = result.advertisementData.advName.trim();
      final platformName = result.device.platformName.trim();
      final advertisesService = result.advertisementData.serviceUuids.any(
        (uuid) => uuid == serviceUuid,
      );
      if (advertisesService ||
          advertisedName == deviceName ||
          platformName == deviceName) {
        discoveredResult = result;
        _setStatus(Esp32BleStatus.deviceFound);
        unawaited(stopScan(updateStatus: false));
        return;
      }
    }
  }

  void _handleStateValue(List<int> value) {
    if (_closed) return;
    final notifiedIntensity = intensityFromState(value);
    if (notifiedIntensity == null) return;
    hasIntensity = true;
    if (!_isAdjustingIntensity) {
      intensity = notifiedIntensity;
      _notify();
    }
  }

  Future<void> _handleUnexpectedDisconnection() async {
    await _cancelPendingIntensityWrites();
    await _cancelDeviceSubscriptions(keepConnectionSubscription: true);
    intensity = 0;
    hasIntensity = false;
    _setStatus(
      Esp32BleStatus.disconnected,
      message:
          'Connection to $deviceName was lost. Tap Reconnect to try again.',
    );
  }

  Future<void> _cancelScanSubscription() async {
    await _scanResultsSubscription?.cancel();
    _scanResultsSubscription = null;
  }

  Future<void> _cancelPendingIntensityWrites() async {
    _writeDebounce?.cancel();
    _writeDebounce = null;
    _pendingIntensity = null;
    _isAdjustingIntensity = false;
    final activeWrite = _writeLoopCompleter?.future;
    if (activeWrite != null) await activeWrite;
  }

  Future<void> _cancelDeviceSubscriptions({
    required bool keepConnectionSubscription,
  }) async {
    final stateCharacteristic = _stateCharacteristic;
    _stateCharacteristic = null;
    _controlCharacteristic = null;

    await _stateValueSubscription?.cancel();
    _stateValueSubscription = null;
    if (stateCharacteristic != null && stateCharacteristic.isNotifying) {
      try {
        await stateCharacteristic.setNotifyValue(false);
      } catch (_) {
        // Notifications are already gone after an unexpected disconnect.
      }
    }

    if (!keepConnectionSubscription) {
      await _connectionSubscription?.cancel();
      _connectionSubscription = null;
    }
  }

  String _adapterMessage(BluetoothAdapterState state) {
    if (state == BluetoothAdapterState.unauthorized) {
      return 'Bluetooth access is not authorized for this app.';
    }
    return 'Bluetooth is turned off. Turn it on to find the ESP32.';
  }

  String _describeError(Object error) {
    final text = error.toString().replaceFirst('Exception: ', '').trim();
    return text.isEmpty ? 'Unknown error' : text;
  }

  void _setError(String message) {
    _setStatus(Esp32BleStatus.error, message: message);
  }

  void _setStatus(Esp32BleStatus next, {String? message}) {
    if (_closed) return;
    status = next;
    errorMessage = message;
    _notify();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }
}
