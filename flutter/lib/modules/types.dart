// Shared Types for Audio Analysis and Animation System
//
// Migrated from state-machine/types.ts after removing external state machine

/// Actor conversation state (detected from audio + subtitle timing)
enum ActorState { idle, speaking }

/// VAD configuration for voice activity detection
class VadConfig {
  /// Low energy threshold for quiet detection
  final double lowEnergyThreshold;

  /// High energy threshold for active speaking detection
  final double highEnergyThreshold;

  /// Pause energy threshold for pause detection
  final double pauseEnergyThreshold;

  /// Weight for Zero Crossing Rate in voice classification
  final double zcrWeight;

  /// Smoothing factor for voice activity (0-1)
  final double smoothingFactor;

  /// Debounce frames to prevent flickering
  final int debounceFrames;

  const VadConfig({
    required this.lowEnergyThreshold,
    required this.highEnergyThreshold,
    required this.pauseEnergyThreshold,
    required this.zcrWeight,
    required this.smoothingFactor,
    required this.debounceFrames,
  });

  VadConfig copyWith({
    double? lowEnergyThreshold,
    double? highEnergyThreshold,
    double? pauseEnergyThreshold,
    double? zcrWeight,
    double? smoothingFactor,
    int? debounceFrames,
  }) {
    return VadConfig(
      lowEnergyThreshold: lowEnergyThreshold ?? this.lowEnergyThreshold,
      highEnergyThreshold: highEnergyThreshold ?? this.highEnergyThreshold,
      pauseEnergyThreshold: pauseEnergyThreshold ?? this.pauseEnergyThreshold,
      zcrWeight: zcrWeight ?? this.zcrWeight,
      smoothingFactor: smoothingFactor ?? this.smoothingFactor,
      debounceFrames: debounceFrames ?? this.debounceFrames,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VadConfig &&
        other.lowEnergyThreshold == lowEnergyThreshold &&
        other.highEnergyThreshold == highEnergyThreshold &&
        other.pauseEnergyThreshold == pauseEnergyThreshold &&
        other.zcrWeight == zcrWeight &&
        other.smoothingFactor == smoothingFactor &&
        other.debounceFrames == debounceFrames;
  }

  @override
  int get hashCode {
    return Object.hash(
      lowEnergyThreshold,
      highEnergyThreshold,
      pauseEnergyThreshold,
      zcrWeight,
      smoothingFactor,
      debounceFrames,
    );
  }
}

/// Pause detection configuration (used by speechHistory module for finish detection)
class PauseDetectionConfig {
  /// Pause detection threshold (frames)
  final int pauseThresholdFrames;

  /// Sustained quiet threshold before finishing (frames)
  final int finishedThresholdFrames;

  /// Zero energy threshold before finishing (frames)
  final int zeroEnergyFrames;

  /// Minimum frames after subtitle before allowing finish (frames)
  final int minFramesAfterSubtitle;

  /// Minimum idle duration for hysteresis recovery (frames)
  final int minIdleDuration;

  /// Strong signal multiplier for hysteresis recovery (multiplier)
  final double strongSignalMultiplier;

  const PauseDetectionConfig({
    required this.pauseThresholdFrames,
    required this.finishedThresholdFrames,
    required this.zeroEnergyFrames,
    required this.minFramesAfterSubtitle,
    required this.minIdleDuration,
    required this.strongSignalMultiplier,
  });

  PauseDetectionConfig copyWith({
    int? pauseThresholdFrames,
    int? finishedThresholdFrames,
    int? zeroEnergyFrames,
    int? minFramesAfterSubtitle,
    int? minIdleDuration,
    double? strongSignalMultiplier,
  }) {
    return PauseDetectionConfig(
      pauseThresholdFrames: pauseThresholdFrames ?? this.pauseThresholdFrames,
      finishedThresholdFrames:
          finishedThresholdFrames ?? this.finishedThresholdFrames,
      zeroEnergyFrames: zeroEnergyFrames ?? this.zeroEnergyFrames,
      minFramesAfterSubtitle:
          minFramesAfterSubtitle ?? this.minFramesAfterSubtitle,
      minIdleDuration: minIdleDuration ?? this.minIdleDuration,
      strongSignalMultiplier:
          strongSignalMultiplier ?? this.strongSignalMultiplier,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PauseDetectionConfig &&
        other.pauseThresholdFrames == pauseThresholdFrames &&
        other.finishedThresholdFrames == finishedThresholdFrames &&
        other.zeroEnergyFrames == zeroEnergyFrames &&
        other.minFramesAfterSubtitle == minFramesAfterSubtitle &&
        other.minIdleDuration == minIdleDuration &&
        other.strongSignalMultiplier == strongSignalMultiplier;
  }

  @override
  int get hashCode {
    return Object.hash(
      pauseThresholdFrames,
      finishedThresholdFrames,
      zeroEnergyFrames,
      minFramesAfterSubtitle,
      minIdleDuration,
      strongSignalMultiplier,
    );
  }
}
