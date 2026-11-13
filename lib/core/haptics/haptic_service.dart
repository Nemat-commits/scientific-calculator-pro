import 'dart:async';

import 'package:flutter/services.dart';

/// Tactile pulse patterns.
enum HapticPattern {
  /// Digit and function keys.
  light,

  /// Operators, tab changes, `=`.
  medium,

  /// Destructive keys (`AC`).
  heavy,

  /// A calculation failed.
  error,
}

/// Dispatches haptic feedback; can be muted from the settings.
class HapticService {
  HapticService({this.enabled = true});

  /// Master switch.
  bool enabled;

  /// Plays [pattern] (no-op while muted or on platforms without a vibrator).
  void play(HapticPattern pattern) {
    if (!enabled) return;
    switch (pattern) {
      case HapticPattern.light:
        unawaited(HapticFeedback.lightImpact());
      case HapticPattern.medium:
        unawaited(HapticFeedback.mediumImpact());
      case HapticPattern.heavy:
        unawaited(HapticFeedback.heavyImpact());
      case HapticPattern.error:
        // Two heavy pulses read as "rejected".
        unawaited(HapticFeedback.heavyImpact());
        Timer(const Duration(milliseconds: 90), () => unawaited(HapticFeedback.heavyImpact()));
    }
  }

  void light() => play(HapticPattern.light);
  void medium() => play(HapticPattern.medium);
  void heavy() => play(HapticPattern.heavy);
  void error() => play(HapticPattern.error);
}

/// A haptic service that never vibrates (tests, web).
class SilentHapticService extends HapticService {
  SilentHapticService() : super(enabled: false);

  @override
  void play(HapticPattern pattern) {}
}
