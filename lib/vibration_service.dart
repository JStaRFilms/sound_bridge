import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';

enum VibrationResult {
  played,
  playedWithoutIntensity,
  playedFallback,
  unavailable,
  timedOut,
  failed,
}

class VibrationService {
  const VibrationService();

  Future<VibrationResult> vibrate({
    required int durationMs,
    required int intensity,
  }) async {
    final hasVibrator = await _withTimeout(Vibration.hasVibrator());

    final clampedDuration = durationMs.clamp(50, 5000);
    final clampedIntensity = intensity.clamp(1, 255);

    if (hasVibrator == false) {
      return _fallbackVibrate(clampedDuration);
    }

    final hasAmplitudeControl =
        await _withTimeout(Vibration.hasAmplitudeControl()) ?? false;

    try {
      final vibration = Vibration.vibrate(
        duration: clampedDuration,
        amplitude: hasAmplitudeControl ? clampedIntensity : -1,
      );

      await vibration.timeout(const Duration(milliseconds: 700));
    } on TimeoutException {
      final fallbackResult = await _fallbackVibrate(clampedDuration);

      return fallbackResult == VibrationResult.playedFallback
          ? fallbackResult
          : VibrationResult.timedOut;
    } catch (_) {
      final fallbackResult = await _fallbackVibrate(clampedDuration);

      return fallbackResult == VibrationResult.playedFallback
          ? fallbackResult
          : VibrationResult.failed;
    }

    return hasAmplitudeControl
        ? VibrationResult.played
        : VibrationResult.playedWithoutIntensity;
  }

  Future<T?> _withTimeout<T>(Future<T> future) async {
    try {
      return await future.timeout(const Duration(milliseconds: 700));
    } catch (_) {
      return null;
    }
  }

  Future<VibrationResult> _fallbackVibrate(int durationMs) async {
    try {
      final endTime = DateTime.now().add(Duration(milliseconds: durationMs));

      do {
        await HapticFeedback.vibrate();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      } while (DateTime.now().isBefore(endTime));

      return VibrationResult.playedFallback;
    } catch (_) {
      return VibrationResult.unavailable;
    }
  }
}
