import 'dart:math';
import '../config/eyes_config.dart';

/// Debug log callback type
typedef DebugLogCallback = void Function(String message);

/// Blink mode types
enum BlinkMode { slow, fast, double_ }

/// Blink phase states
enum BlinkPhase { none, closing, closed, opening }

/// Eyes state
enum EyesState { open, closed }

/// Internal blink state tracking
class _BlinkState {
  bool isActive = false;
  BlinkPhase phase = BlinkPhase.none;
  int startTime = 0; // Phase start time (reset for each phase)
  int nextBlinkTime = 0;
  BlinkMode mode = BlinkMode.fast; // Default fast blink
  int currentBlinkCount = 0; // For double mode, track current completed phases
  int targetBlinkCount = 1; // For double mode, target phase count
  double closeDuration = 250; // Current phase close duration
  double openDuration = 100; // Current phase open duration (only double mode uses this)
}

/// Eyes State Manager
///
/// Manages eye blinking animations with three modes:
/// - slow: Calm, natural blinking
/// - fast: Quick, energetic blinking
/// - double: Rapid successive blinks
class EyesStateManager {
  final ActorState Function() getLifecycleState;
  final EyesLifecycleConfig lifecycleConfig;
  final EyesTimingConfig timingConfig;
  final DebugLogCallback? onDebugLog;

  EyesState _currentEyesState = EyesState.open;
  final _BlinkState _blinkState = _BlinkState();
  final Random _random = Random();

  /// Track last blink end time for interval logging (END-to-START measurement)
  int _lastBlinkEndTime = 0;

  EyesStateManager({
    required this.getLifecycleState,
    EyesLifecycleConfig? lifecycleConfig,
    EyesTimingConfig? timingConfig,
    this.onDebugLog,
  })  : lifecycleConfig = lifecycleConfig ?? defaultEyesLifecycleConfig,
        timingConfig = timingConfig ?? defaultEyesTimingConfig {
    _scheduleNextBlink();
  }

  void _log(String message) {
    onDebugLog?.call(message);
  }

  /// Generic timing generation: base ± variance
  double _generateTiming(TimingParams params) {
    return params.base + (_random.nextDouble() * 2 - 1) * params.variance;
  }

  /// Generate slow blink duration (using config)
  double _generateSlowBlinkDuration() {
    return _generateTiming(timingConfig.slowBlinkDuration);
  }

  /// Generate fast blink duration (using config)
  double _generateFastBlinkDuration() {
    return _generateTiming(timingConfig.fastBlinkDuration);
  }

  /// Generate double blink single phase duration (using config)
  double _generateDoubleBlinkPhaseDuration() {
    return _generateTiming(timingConfig.doubleBlinkPhaseDuration);
  }

  /// Generate blink interval (using config)
  double _generateBlinkInterval() {
    return _generateTiming(timingConfig.blinkInterval);
  }

  /// Select blink mode based on CURRENT lifecycle state
  /// Called when blink is about to start (not when scheduling)
  void _selectBlinkMode() {
    final config = lifecycleConfig[getLifecycleState()];

    // Randomly select blink mode based on probability
    final rand = _random.nextDouble();
    final probabilities = config.modeProbability;

    if (rand < probabilities.slow) {
      // Slow blink: use config
      _blinkState.mode = BlinkMode.slow;
      _blinkState.closeDuration = _generateSlowBlinkDuration();
      _blinkState.targetBlinkCount = 1;
    } else if (rand < probabilities.slow + probabilities.fast) {
      // Fast blink: use config
      _blinkState.mode = BlinkMode.fast;
      _blinkState.closeDuration = _generateFastBlinkDuration();
      _blinkState.targetBlinkCount = 1;
    } else {
      // Double blink: use config
      _blinkState.mode = BlinkMode.double_;
      _blinkState.closeDuration = _generateDoubleBlinkPhaseDuration();
      _blinkState.openDuration = _generateDoubleBlinkPhaseDuration();
      _blinkState.targetBlinkCount = 2; // Need to complete 2 closing phases
    }
    _blinkState.currentBlinkCount = 0;
  }

  void _scheduleNextBlink() {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Only schedule time, don't select mode (mode will be selected when blink starts)
    final interval = _generateBlinkInterval();
    _blinkState.nextBlinkTime = now + interval.round();
  }

  bool _shouldStartBlink() {
    final config = lifecycleConfig[getLifecycleState()];
    if (!config.blinkEnabled) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    return now >= _blinkState.nextBlinkTime &&
        _blinkState.phase == BlinkPhase.none;
  }

  /// Finish blink and schedule next one
  void _finishBlink() {
    _currentEyesState = EyesState.open;
    _blinkState.isActive = false;
    _blinkState.phase = BlinkPhase.none;
    _lastBlinkEndTime = DateTime.now().millisecondsSinceEpoch;
    _scheduleNextBlink();
  }

  void _processBlink() {
    if (!_blinkState.isActive) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final duration = now - _blinkState.startTime;

    if (_blinkState.mode == BlinkMode.slow ||
        _blinkState.mode == BlinkMode.fast) {
      // Slow/fast blink: just close eyes for a duration
      if (_blinkState.phase == BlinkPhase.closing &&
          duration >= _blinkState.closeDuration) {
        // LOG: Blink end duration
        final durationConfig = _blinkState.mode == BlinkMode.slow
            ? timingConfig.slowBlinkDuration
            : timingConfig.fastBlinkDuration;
        final durationRange =
            '${(durationConfig.base - durationConfig.variance).toStringAsFixed(0)}-${(durationConfig.base + durationConfig.variance).toStringAsFixed(0)}ms';
        _log(
            '[BLINK END] ${getLifecycleState().name} ${_blinkState.mode.name} - actual duration: ${duration}ms (config: $durationRange)');

        _finishBlink();
      }
    } else {
      // Double blink: close → open → close
      if (_blinkState.phase == BlinkPhase.closing) {
        // Closing phase
        if (duration >= _blinkState.closeDuration) {
          _blinkState.currentBlinkCount++;
          _log(
              '[DOUBLE BLINK] Phase ${_blinkState.currentBlinkCount}/3: closed ${_blinkState.closeDuration.toStringAsFixed(1)}ms');

          if (_blinkState.currentBlinkCount == 1) {
            // First close complete → open
            _blinkState.phase = BlinkPhase.opening;
            _blinkState.startTime = DateTime.now().millisecondsSinceEpoch;
            _currentEyesState = EyesState.open;
          } else if (_blinkState.currentBlinkCount == 2) {
            // LOG: Double blink end (total duration from startTime - same as TypeScript)
            // Note: TypeScript uses this.blinkState.startTime here which gets reset,
            // so the totalDuration only reflects the last phase duration
            final totalDuration =
                DateTime.now().millisecondsSinceEpoch - _blinkState.startTime;
            final phaseConfig = timingConfig.doubleBlinkPhaseDuration;
            final phaseRange =
                '${(phaseConfig.base - phaseConfig.variance).toStringAsFixed(0)}-${(phaseConfig.base + phaseConfig.variance).toStringAsFixed(0)}ms';
            _log(
                '[BLINK END] ${getLifecycleState().name} double - total duration: ${totalDuration}ms (phase config: $phaseRange each)');

            _finishBlink();
          }
        }
      } else if (_blinkState.phase == BlinkPhase.opening) {
        // Opening phase
        if (duration >= _blinkState.openDuration) {
          _log(
              '[DOUBLE BLINK] Phase 2/3: opened ${_blinkState.openDuration.toStringAsFixed(1)}ms');
          // Open complete → start second close
          _blinkState.phase = BlinkPhase.closing;
          _blinkState.startTime = DateTime.now().millisecondsSinceEpoch;
          _blinkState.closeDuration =
              _generateDoubleBlinkPhaseDuration(); // Generate new close duration
          _currentEyesState = EyesState.closed;
        }
      }
    }
  }

  /// Update eyes state - call this every frame
  EyesState update() {
    if (_shouldStartBlink()) {
      final now = DateTime.now().millisecondsSinceEpoch;

      // Select blink mode based on CURRENT state (not stale state from scheduling)
      _selectBlinkMode();

      // LOG: Blink interval (time since last blink ended - END-to-START measurement)
      final interval = _lastBlinkEndTime == 0 ? 0 : now - _lastBlinkEndTime;
      final intervalConfig = timingConfig.blinkInterval;
      final intervalRange =
          '${(intervalConfig.base - intervalConfig.variance).toStringAsFixed(0)}-${(intervalConfig.base + intervalConfig.variance).toStringAsFixed(0)}ms';
      _log(
          '[BLINK START] ${getLifecycleState().name} ${_blinkState.mode.name} - interval: ${interval}ms (config: $intervalRange)');

      _blinkState.isActive = true;
      _blinkState.phase = BlinkPhase.closing;
      _blinkState.startTime = now;
      _currentEyesState = EyesState.closed; // Start blink, immediately close
    }

    _processBlink();

    return _currentEyesState;
  }

  /// Get current eyes state (without triggering update)
  EyesState getCurrentEyesState() {
    return _currentEyesState;
  }

  /// Update and get eyes state (call this every frame)
  EyesState updateAndGetEyesState() {
    return update();
  }

  /// Check if currently blinking
  bool isCurrentlyBlinking() {
    return _blinkState.isActive;
  }

  /// Get debug information
  Map<String, dynamic> getDebugInfo() {
    return {
      'lifecycleState': getLifecycleState().name,
      'eyesState': _currentEyesState.name,
      'blinkActive': _blinkState.isActive,
      'blinkPhase': _blinkState.phase.name,
      'blinkMode': _blinkState.mode.name,
      'blinkProgress': _blinkState.mode == BlinkMode.double_
          ? '${_blinkState.currentBlinkCount}/2'
          : _blinkState.isActive
              ? 'active'
              : 'idle',
      'nextBlinkIn':
          max(0, _blinkState.nextBlinkTime - DateTime.now().millisecondsSinceEpoch),
    };
  }

  /// Destroy and cleanup
  void destroy() {
    _blinkState.isActive = false;
    _blinkState.phase = BlinkPhase.none;
  }
}

/// Factory function to create EyesStateManager
EyesStateManager createEyesStateManager({
  required ActorState Function() getLifecycleState,
  EyesLifecycleConfig? lifecycleConfig,
  EyesTimingConfig? timingConfig,
  DebugLogCallback? onDebugLog,
}) {
  return EyesStateManager(
    getLifecycleState: getLifecycleState,
    lifecycleConfig: lifecycleConfig,
    timingConfig: timingConfig,
    onDebugLog: onDebugLog,
  );
}
