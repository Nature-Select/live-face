// Voice Activity Detection (VAD)
//
// Classifies audio into voice activity states and provides smoothing.

import 'dart:math' as math;

import 'types.dart';

// ============================================================================
// Constants
// ============================================================================

const double _zcrWeight = 0.2;
const double _zcrMaxContribution = 0.003;

// ============================================================================
// Types
// ============================================================================

/// Voice activity state
enum VoiceActivityState { quiet, mid, active }

/// Configuration for VoiceActivityManager
class VoiceActivityManagerConfig {
  /// Number of frames for debouncing
  final int debounceFrames;

  /// Smoothing factor (confidence threshold for state transitions, 0-1)
  final double smoothingFactor;

  const VoiceActivityManagerConfig({
    required this.debounceFrames,
    required this.smoothingFactor,
  });
}

// ============================================================================
// Pure Functions
// ============================================================================

/// Classify voice activity based on energy and zero-crossing rate (pure function)
VoiceActivityState classifyVoiceActivity(
  double energy,
  double zcr,
  VadConfig config,
) {
  final lowEnergyThreshold = config.lowEnergyThreshold;
  final highEnergyThreshold = config.highEnergyThreshold;

  if (energy == 0) {
    return VoiceActivityState.quiet;
  }

  final zcrContribution = math.min(zcr * _zcrWeight, _zcrMaxContribution);
  final adjustedEnergy = energy + zcrContribution;

  if (adjustedEnergy <= lowEnergyThreshold) {
    return VoiceActivityState.quiet;
  }

  if (adjustedEnergy >= highEnergyThreshold) {
    return VoiceActivityState.active;
  }

  return VoiceActivityState.mid;
}

// ============================================================================
// VoiceActivityManager Class
// ============================================================================

/// Manages voice activity state with smoothing and debouncing
class VoiceActivityManager {
  VoiceActivityManagerConfig _config;
  final List<VoiceActivityState> _history = [];
  VoiceActivityState _currentState;

  VoiceActivityManager(
    this._config, [
    VoiceActivityState initialState = VoiceActivityState.quiet,
  ]) : _currentState = initialState;

  // ============================================================================
  // Public Methods
  // ============================================================================

  /// Smooth voice activity using debounce and confidence threshold
  VoiceActivityState smooth(VoiceActivityState newActivity) {
    _updateHistory(newActivity);

    if (!_hasEnoughHistory()) {
      return _currentState;
    }

    final mostCommon = _findMostCommonState();
    final confidence = _calculateConfidence(mostCommon);

    if (_shouldTransition(mostCommon, confidence)) {
      _currentState = mostCommon;
    }

    return _currentState;
  }

  /// Update configuration
  void updateConfig(
    VoiceActivityManagerConfig config, [
    VoiceActivityState initialState = VoiceActivityState.quiet,
  ]) {
    _config = config;
    reset(initialState);
  }

  /// Reset to initial state
  void reset([VoiceActivityState initialState = VoiceActivityState.quiet]) {
    _history.clear();
    _currentState = initialState;
  }

  /// Get current state
  VoiceActivityState getCurrentState() {
    return _currentState;
  }

  /// Get debug information
  Map<String, dynamic> getDebugInfo() {
    return {
      'currentState': _currentState.name,
      'historyLength': _history.length,
      'debounceFrames': _config.debounceFrames,
      'smoothingFactor': _config.smoothingFactor,
    };
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  void _updateHistory(VoiceActivityState newActivity) {
    _history.add(newActivity);
    if (_history.length > _config.debounceFrames) {
      _history.removeAt(0);
    }
  }

  bool _hasEnoughHistory() {
    return _history.length >= _config.debounceFrames;
  }

  VoiceActivityState _findMostCommonState() {
    final counts = <VoiceActivityState, int>{
      VoiceActivityState.quiet: 0,
      VoiceActivityState.mid: 0,
      VoiceActivityState.active: 0,
    };

    for (final state in _history) {
      counts[state] = (counts[state] ?? 0) + 1;
    }

    VoiceActivityState mostCommon = _currentState;
    int highestCount = 0;

    for (final state in VoiceActivityState.values) {
      final count = counts[state] ?? 0;
      if (count > highestCount) {
        highestCount = count;
        mostCommon = state;
      }
    }

    return mostCommon;
  }

  double _calculateConfidence(VoiceActivityState state) {
    final count = _history.where((s) => s == state).length;
    return count / _history.length;
  }

  bool _shouldTransition(VoiceActivityState newState, double confidence) {
    final isDifferentState = newState != _currentState;
    final hasEnoughConfidence = confidence >= _config.smoothingFactor;
    return isDifferentState && hasEnoughConfidence;
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/// Create a VoiceActivityManager instance
VoiceActivityManager createVoiceActivityManager(
  VoiceActivityManagerConfig config, [
  VoiceActivityState initialState = VoiceActivityState.quiet,
]) {
  return VoiceActivityManager(config, initialState);
}
