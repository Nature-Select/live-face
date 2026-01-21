// Mouth Animation Configuration
//
// Centralized configuration for mouth animation parameters.
// These parameters control visual mouth movements based on audio features.
// They do NOT affect state transitions (IDLE ↔ SPEAKING).

/// Audio Feature Weights for Mouth Intensity Calculation
///
/// These weights determine how much each audio feature contributes
/// to the combined intensity calculation.
class MouthFeatureWeights {
  /// Weight for energy (RMS) feature
  final double energy;

  /// Weight for Zero Crossing Rate (ZCR) feature
  final double zcr;

  /// Weight for spectral centroid feature
  final double spectralCentroid;

  /// Weight for high frequency energy feature
  final double highFreqEnergy;

  const MouthFeatureWeights({
    required this.energy,
    required this.zcr,
    required this.spectralCentroid,
    required this.highFreqEnergy,
  });

  MouthFeatureWeights copyWith({
    double? energy,
    double? zcr,
    double? spectralCentroid,
    double? highFreqEnergy,
  }) {
    return MouthFeatureWeights(
      energy: energy ?? this.energy,
      zcr: zcr ?? this.zcr,
      spectralCentroid: spectralCentroid ?? this.spectralCentroid,
      highFreqEnergy: highFreqEnergy ?? this.highFreqEnergy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MouthFeatureWeights &&
        other.energy == energy &&
        other.zcr == zcr &&
        other.spectralCentroid == spectralCentroid &&
        other.highFreqEnergy == highFreqEnergy;
  }

  @override
  int get hashCode {
    return Object.hash(energy, zcr, spectralCentroid, highFreqEnergy);
  }
}

/// Mouth Animation Configuration
///
/// Complete configuration for mouth animation behavior.
class MouthConfig {
  // Basic thresholds

  /// Energy threshold below which mouth closes
  final double mouthCloseThreshold;

  /// Maximum frames mouth can stay open before decay activates
  final int maxMouthOpenDuration;

  /// Energy threshold for detecting micro-pauses
  final double microPauseThreshold;

  /// Factor for adaptive threshold calculation (0-1)
  final double adaptiveThresholdFactor;

  /// Decay rate for mouth intensity during prolonged opening (0-1)
  final double mouthDecayRate;

  /// Decay threshold: intensity value below which mouth closes during decay
  final double decayClosedThreshold;

  // Energy history parameters

  /// Size of energy history window (frames)
  final int energyHistoryWindow;

  /// Window size for recent energy average (frames)
  final int recentAvgWindow;

  /// Window size for older energy average (frames)
  final int olderAvgWindow;

  /// Minimum energy values required before enabling adaptive threshold
  final int minEnergyValuesForAdaptive;

  // Energy drop detection

  /// Multiplier for detecting energy drops (0-1)
  final double energyDropMultiplier;

  // Feature weights for intensity calculation

  /// Weights for combining audio features into mouth intensity
  final MouthFeatureWeights featureWeights;

  const MouthConfig({
    required this.mouthCloseThreshold,
    required this.maxMouthOpenDuration,
    required this.microPauseThreshold,
    required this.adaptiveThresholdFactor,
    required this.mouthDecayRate,
    required this.decayClosedThreshold,
    required this.energyHistoryWindow,
    required this.recentAvgWindow,
    required this.olderAvgWindow,
    required this.minEnergyValuesForAdaptive,
    required this.energyDropMultiplier,
    required this.featureWeights,
  });

  MouthConfig copyWith({
    double? mouthCloseThreshold,
    int? maxMouthOpenDuration,
    double? microPauseThreshold,
    double? adaptiveThresholdFactor,
    double? mouthDecayRate,
    double? decayClosedThreshold,
    int? energyHistoryWindow,
    int? recentAvgWindow,
    int? olderAvgWindow,
    int? minEnergyValuesForAdaptive,
    double? energyDropMultiplier,
    MouthFeatureWeights? featureWeights,
  }) {
    return MouthConfig(
      mouthCloseThreshold: mouthCloseThreshold ?? this.mouthCloseThreshold,
      maxMouthOpenDuration: maxMouthOpenDuration ?? this.maxMouthOpenDuration,
      microPauseThreshold: microPauseThreshold ?? this.microPauseThreshold,
      adaptiveThresholdFactor:
          adaptiveThresholdFactor ?? this.adaptiveThresholdFactor,
      mouthDecayRate: mouthDecayRate ?? this.mouthDecayRate,
      decayClosedThreshold: decayClosedThreshold ?? this.decayClosedThreshold,
      energyHistoryWindow: energyHistoryWindow ?? this.energyHistoryWindow,
      recentAvgWindow: recentAvgWindow ?? this.recentAvgWindow,
      olderAvgWindow: olderAvgWindow ?? this.olderAvgWindow,
      minEnergyValuesForAdaptive:
          minEnergyValuesForAdaptive ?? this.minEnergyValuesForAdaptive,
      energyDropMultiplier: energyDropMultiplier ?? this.energyDropMultiplier,
      featureWeights: featureWeights ?? this.featureWeights,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MouthConfig &&
        other.mouthCloseThreshold == mouthCloseThreshold &&
        other.maxMouthOpenDuration == maxMouthOpenDuration &&
        other.microPauseThreshold == microPauseThreshold &&
        other.adaptiveThresholdFactor == adaptiveThresholdFactor &&
        other.mouthDecayRate == mouthDecayRate &&
        other.decayClosedThreshold == decayClosedThreshold &&
        other.energyHistoryWindow == energyHistoryWindow &&
        other.recentAvgWindow == recentAvgWindow &&
        other.olderAvgWindow == olderAvgWindow &&
        other.minEnergyValuesForAdaptive == minEnergyValuesForAdaptive &&
        other.energyDropMultiplier == energyDropMultiplier &&
        other.featureWeights == featureWeights;
  }

  @override
  int get hashCode {
    return Object.hash(
      mouthCloseThreshold,
      maxMouthOpenDuration,
      microPauseThreshold,
      adaptiveThresholdFactor,
      mouthDecayRate,
      decayClosedThreshold,
      energyHistoryWindow,
      recentAvgWindow,
      olderAvgWindow,
      minEnergyValuesForAdaptive,
      energyDropMultiplier,
      featureWeights,
    );
  }
}

/// Default Mouth Animation Configuration
///
/// These values are optimized for natural-looking mouth movements
/// synchronized with real-time audio.
const defaultMouthConfig = MouthConfig(
  // Basic thresholds
  mouthCloseThreshold: 0.001, // Energy below this closes mouth
  maxMouthOpenDuration: 18, // 0.75s max open (18 frames @ 24fps)
  microPauseThreshold: 0.001, // Micro-pause detection threshold
  adaptiveThresholdFactor: 0.78, // 78% of average energy
  mouthDecayRate: 0.85, // 85% decay rate (15% reduction per frame)
  decayClosedThreshold: 0.5, // Below 0.5 intensity value = closed

  // Energy history parameters
  energyHistoryWindow: 9, // Track last 9 frames of energy
  recentAvgWindow: 4, // Last 4 frames for recent average
  olderAvgWindow: 5, // First 5 frames for older average
  minEnergyValuesForAdaptive:
      6, // Need 6 values before adaptive threshold activates

  // Energy drop detection
  energyDropMultiplier: 0.6, // Recent average < 60% of older average = drop

  // Feature weights for intensity calculation
  featureWeights: MouthFeatureWeights(
    energy: 0.4, // 40% contribution from RMS energy
    zcr: 0.2, // 20% contribution from zero crossing rate
    spectralCentroid: 0.0001, // 0.01% contribution from spectral centroid
    highFreqEnergy: 0.4, // 40% contribution from high frequency energy
  ),
);
