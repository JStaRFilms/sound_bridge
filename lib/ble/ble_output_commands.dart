class PwmHardwareState {
  const PwmHardwareState({
    required this.intensity,
    required this.durationSeconds,
  });

  final int intensity;
  final int durationSeconds;

  bool get isRunning => intensity > 0;
}

abstract interface class BleOutputCommands {
  bool get isConnected;
  bool get commandInProgress;
  Stream<PwmHardwareState> get hardwareStates;

  Future<bool> sendOutputCommand({
    required int intensity,
    required int durationSeconds,
  });
}
