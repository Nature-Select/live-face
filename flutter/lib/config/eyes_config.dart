// Eyes Configuration
//
// Centralized configuration for eye blinking system.
// Controls blinking behavior in different lifecycle states (IDLE, SPEAKING).

import '../modules/types.dart';

export '../modules/types.dart' show ActorState;

/// Blink Mode Probability
///
/// Probability distribution for different blink modes.
/// Values should sum to approximately 1.0 (or less if no-blink is desired).
class BlinkModeProbability {
  /// Probability for slow blink mode (0-1)
  final double slow;

  /// Probability for fast blink mode (0-1)
  final double fast;

  /// Probability for double blink mode (0-1)
  final double double_;

  const BlinkModeProbability({
    required this.slow,
    required this.fast,
    required this.double_,
  });
}

/// Eyes Lifecycle State Configuration
///
/// Configuration for a specific lifecycle state (IDLE or SPEAKING).
class EyesLifecycleStateConfig {
  /// Whether blinking is enabled in this state
  final bool blinkEnabled;

  /// Probability distribution for blink modes
  final BlinkModeProbability modeProbability;

  const EyesLifecycleStateConfig({
    required this.blinkEnabled,
    required this.modeProbability,
  });
}

/// Eyes Lifecycle Configuration
///
/// Complete lifecycle configuration mapping states to their configs.
class EyesLifecycleConfig {
  /// Configuration for IDLE state (agent connected but not speaking)
  final EyesLifecycleStateConfig idle;

  /// Configuration for SPEAKING state (agent actively speaking)
  final EyesLifecycleStateConfig speaking;

  const EyesLifecycleConfig({
    required this.idle,
    required this.speaking,
  });

  EyesLifecycleStateConfig operator [](ActorState state) {
    switch (state) {
      case ActorState.idle:
        return idle;
      case ActorState.speaking:
        return speaking;
    }
  }
}

/// Default Eyes Lifecycle Configuration
///
/// Optimized probabilities:
/// - IDLE: 90% slow blink, 10% double blink (calm, natural blinking)
/// - SPEAKING: 100% fast blink (energetic, engaged speaking)
const defaultEyesLifecycleConfig = EyesLifecycleConfig(
  idle: EyesLifecycleStateConfig(
    blinkEnabled: true,
    modeProbability: BlinkModeProbability(
      slow: 0.9, // 90% slow blink (calm, natural)
      fast: 0, // 0% fast blink
      double_: 0.1, // 10% double blink (occasional variation)
    ),
  ),
  speaking: EyesLifecycleStateConfig(
    blinkEnabled: true,
    modeProbability: BlinkModeProbability(
      slow: 0, // 0% slow blink
      fast: 1, // 100% fast blink (energetic, speaking)
      double_: 0, // 0% double blink
    ),
  ),
);

/// Timing Parameters
///
/// Base duration and variance for generating randomized timing.
/// Actual timing = base ± variance (uniform random distribution).
class TimingParams {
  /// Base duration in milliseconds
  final double base;

  /// Variance in milliseconds (±)
  final double variance;

  const TimingParams({
    required this.base,
    required this.variance,
  });
}

/// Eyes Timing Configuration
///
/// Controls timing for different blink modes and intervals.
class EyesTimingConfig {
  /// Slow blink duration (500ms ± 100ms = 400-600ms)
  final TimingParams slowBlinkDuration;

  /// Fast blink duration (250ms ± 50ms = 200-300ms)
  final TimingParams fastBlinkDuration;

  /// Double blink single phase duration (100ms ± 20ms = 80-120ms)
  final TimingParams doubleBlinkPhaseDuration;

  /// Blink interval between blinks (2000ms ± 300ms = 1700-2300ms)
  final TimingParams blinkInterval;

  const EyesTimingConfig({
    required this.slowBlinkDuration,
    required this.fastBlinkDuration,
    required this.doubleBlinkPhaseDuration,
    required this.blinkInterval,
  });
}

/// Default Eyes Timing Configuration
///
/// Optimized for natural-looking blinking behavior:
/// - Slow blink: ~0.5s (calm, natural)
/// - Fast blink: ~0.25s (quick, speaking)
/// - Double blink phase: ~0.1s (rapid succession)
/// - Blink interval: ~2s (natural human blinking frequency)
const defaultEyesTimingConfig = EyesTimingConfig(
  slowBlinkDuration: TimingParams(
    base: 400, // 0.4 seconds base
    variance: 100, // ±0.1 seconds
  ),
  fastBlinkDuration: TimingParams(
    base: 250, // 0.25 seconds base
    variance: 50, // ±0.05 seconds
  ),
  doubleBlinkPhaseDuration: TimingParams(
    base: 100, // 0.1 seconds base
    variance: 20, // ±0.02 seconds
  ),
  blinkInterval: TimingParams(
    base: 3500, // 3.5 seconds base
    variance: 800, // ±0.8 seconds
  ),
);
