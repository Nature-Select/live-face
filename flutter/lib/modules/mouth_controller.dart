// Mouth Controller
//
// Controls mouth animation based on audio features and actor state.

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config/mouth_config.dart';
import 'types.dart';

/// Mouth intensity state
enum MouthIntensity { closed, open }

/// Audio feature set for mouth animation
class AudioFeatureSet {
  final double energy;
  final double zcr;
  final double spectralCentroid;
  final double highFreqEnergy;

  const AudioFeatureSet({
    required this.energy,
    required this.zcr,
    required this.spectralCentroid,
    required this.highFreqEnergy,
  });

  /// Create from VoiceMetrics
  factory AudioFeatureSet.fromMetrics({
    required double energy,
    required double zcr,
    required double spectralCentroid,
    required double highFreqEnergy,
  }) {
    return AudioFeatureSet(
      energy: energy,
      zcr: zcr,
      spectralCentroid: spectralCentroid,
      highFreqEnergy: highFreqEnergy,
    );
  }
}

/// Internal mouth controller state
class MouthControllerState {
  MouthIntensity currentIntensity;
  int framesOpen;
  List<double> lastEnergyValues;
  double adaptiveThreshold;
  bool decayActive;

  MouthControllerState({
    required this.currentIntensity,
    required this.framesOpen,
    required this.lastEnergyValues,
    required this.adaptiveThreshold,
    required this.decayActive,
  });

  MouthControllerState copyWith({
    MouthIntensity? currentIntensity,
    int? framesOpen,
    List<double>? lastEnergyValues,
    double? adaptiveThreshold,
    bool? decayActive,
  }) {
    return MouthControllerState(
      currentIntensity: currentIntensity ?? this.currentIntensity,
      framesOpen: framesOpen ?? this.framesOpen,
      lastEnergyValues: lastEnergyValues ?? List.from(this.lastEnergyValues),
      adaptiveThreshold: adaptiveThreshold ?? this.adaptiveThreshold,
      decayActive: decayActive ?? this.decayActive,
    );
  }
}

/// Mouth Controller
///
/// Controls mouth animation based on audio features and actor state.
class MouthController {
  final ActorState Function() getLifecycleState;
  final VadConfig vadConfig;
  MouthConfig _mouthConfig;
  late MouthControllerState _mouthState;

  MouthController({
    required this.getLifecycleState,
    required this.vadConfig,
    MouthConfig? mouthConfig,
  }) : _mouthConfig = mouthConfig ?? defaultMouthConfig {
    _mouthState = _createInitialState();
  }

  MouthControllerState _createInitialState() {
    return MouthControllerState(
      currentIntensity: MouthIntensity.closed,
      framesOpen: 0,
      lastEnergyValues: [],
      adaptiveThreshold: vadConfig.lowEnergyThreshold,
      decayActive: false,
    );
  }

  /// Reset controller state
  void reset() {
    _mouthState = _createInitialState();
  }

  /// Update configuration
  void updateConfig(MouthConfig config) {
    _mouthConfig = config;
    debugPrint('[MOUTH CONFIG] Updated');
  }

  /// Get current configuration
  MouthConfig getConfig() {
    return _mouthConfig;
  }

  void _updateEnergyHistory(double energy) {
    _mouthState.lastEnergyValues.add(energy);
    if (_mouthState.lastEnergyValues.length > _mouthConfig.energyHistoryWindow) {
      _mouthState.lastEnergyValues.removeAt(0);
    }
  }

  ({double recentAvg, double olderAvg}) _calculateEnergyAverages() {
    final values = _mouthState.lastEnergyValues;
    final config = _mouthConfig;

    double recentAvg = 0;
    final recentSlice = values.length >= config.recentAvgWindow
        ? values.sublist(values.length - config.recentAvgWindow)
        : values;
    if (recentSlice.isNotEmpty) {
      recentAvg = recentSlice.reduce((a, b) => a + b) / config.recentAvgWindow;
    }

    double olderAvg = 0;
    final olderSlice = values.length >= config.olderAvgWindow
        ? values.sublist(0, config.olderAvgWindow)
        : values;
    if (olderSlice.isNotEmpty) {
      olderAvg = olderSlice.reduce((a, b) => a + b) / config.olderAvgWindow;
    }

    return (recentAvg: recentAvg, olderAvg: olderAvg);
  }

  bool _isEnergyDropping(double recentAvg, double olderAvg) {
    final config = _mouthConfig;
    return recentAvg < olderAvg * config.energyDropMultiplier &&
        olderAvg > config.microPauseThreshold;
  }

  void _updateAdaptiveThreshold() {
    final values = _mouthState.lastEnergyValues;
    final config = _mouthConfig;

    if (values.length >= config.minEnergyValuesForAdaptive) {
      final avgEnergy = values.reduce((a, b) => a + b) / values.length;
      _mouthState.adaptiveThreshold = math.max(
        config.mouthCloseThreshold,
        avgEnergy * config.adaptiveThresholdFactor,
      );
    }
  }

  double _calculateCombinedIntensity(AudioFeatureSet features) {
    final weights = _mouthConfig.featureWeights;
    return features.energy * weights.energy +
        features.zcr * weights.zcr +
        features.spectralCentroid * weights.spectralCentroid +
        features.highFreqEnergy * weights.highFreqEnergy;
  }

  void _closeMouth() {
    _mouthState.framesOpen = 0;
    _mouthState.decayActive = false;
    _mouthState.currentIntensity = MouthIntensity.closed;
  }

  void _applyDecay() {
    if (!_mouthState.decayActive) return;

    // For binary state, decay simply closes the mouth when active
    if (_mouthState.currentIntensity == MouthIntensity.open) {
      final decayedValue = 1 * _mouthConfig.mouthDecayRate;
      if (decayedValue < _mouthConfig.decayClosedThreshold) {
        _closeMouth();
      }
    }
  }

  /// Update mouth state based on current lifecycle state and audio features.
  ///
  /// @param features - Audio analysis features
  /// @returns Current mouth intensity
  MouthIntensity update(AudioFeatureSet features) {
    final actorState = getLifecycleState();

    // IDLE: always closed
    if (actorState == ActorState.idle) {
      _closeMouth();
      return MouthIntensity.closed;
    }

    // SPEAKING: calculate mouth intensity from audio features
    _updateEnergyHistory(features.energy);

    final averages = _calculateEnergyAverages();
    final energyDropping = _isEnergyDropping(averages.recentAvg, averages.olderAvg);

    _updateAdaptiveThreshold();

    // Close mouth on low energy or energy drop
    if (features.energy <= _mouthConfig.mouthCloseThreshold || energyDropping) {
      _closeMouth();
      return _mouthState.currentIntensity;
    }

    // Calculate combined intensity and classify
    final combinedIntensity = _calculateCombinedIntensity(features);
    _mouthState.currentIntensity = combinedIntensity < _mouthState.adaptiveThreshold
        ? MouthIntensity.closed
        : MouthIntensity.open;

    // Update frames open counter
    if (_mouthState.currentIntensity != MouthIntensity.closed) {
      _mouthState.framesOpen++;
    } else {
      _closeMouth();
    }

    // Activate decay if mouth has been open too long
    if (_mouthState.framesOpen > _mouthConfig.maxMouthOpenDuration) {
      _mouthState.decayActive = true;
    }

    _applyDecay();

    return _mouthState.currentIntensity;
  }

  /// Get current state (readonly copy)
  MouthControllerState getState() {
    return _mouthState.copyWith();
  }
}

/// Create a MouthController instance
MouthController createMouthController({
  required ActorState Function() getLifecycleState,
  required VadConfig vadConfig,
  MouthConfig? mouthConfig,
}) {
  return MouthController(
    getLifecycleState: getLifecycleState,
    vadConfig: vadConfig,
    mouthConfig: mouthConfig,
  );
}
