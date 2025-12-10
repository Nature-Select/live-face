// Speech History Manager
//
// Tracks speech history for pause detection and finish conditions.

import 'package:flutter/foundation.dart';

import 'types.dart';
import 'vad.dart';

// ============================================================================
// Constants
// ============================================================================

const double _zeroEnergyThreshold = 0.000001;

// ============================================================================
// Types
// ============================================================================

/// Input for speech history update
class SpeechHistoryInput {
  final VoiceActivityState voiceActivity;
  final double energy;
  final int frame;

  const SpeechHistoryInput({
    required this.voiceActivity,
    required this.energy,
    required this.frame,
  });
}

/// Result of speech history update
class SpeechHistoryUpdateResult {
  final bool shouldTriggerPauseCheck;
  final bool shouldFinishSpeaking;
  final String? finishReason; // 'sustained_quiet' | 'zero_energy'
  final bool shouldMarkPauseExpressionIdle;
  final int framesSinceLastSubtitle;
  final bool shouldResumeFromIdle;

  const SpeechHistoryUpdateResult({
    required this.shouldTriggerPauseCheck,
    required this.shouldFinishSpeaking,
    this.finishReason,
    required this.shouldMarkPauseExpressionIdle,
    required this.framesSinceLastSubtitle,
    required this.shouldResumeFromIdle,
  });
}

// ============================================================================
// SpeechHistoryManager Class
// ============================================================================

/// Manages speech history for pause detection and finish conditions
class SpeechHistoryManager {
  final VadConfig vadConfig;
  final PauseDetectionConfig pauseDetectionConfig;

  // Internal State
  final List<VoiceActivityState> _recentActivity = [];
  int _lastActiveFrame = 0;
  int _consecutiveQuietFrames = 0;
  int _consecutivePauseFrames = 0;
  int _consecutiveZeroEnergyFrames = 0;
  bool _isInSustainedQuiet = false;
  int _lastSubtitleFrame = 0;
  int _idleStateStartFrame = 0;

  SpeechHistoryManager({
    required this.vadConfig,
    required this.pauseDetectionConfig,
  });

  // ============================================================================
  // Public Methods
  // ============================================================================

  /// Record the frame when a subtitle was displayed
  void recordSubtitleFrame(int frame) {
    _lastSubtitleFrame = frame;
  }

  /// Set the frame when idle state started
  void setIdleStateStartFrame(int frame) {
    _idleStateStartFrame = frame;
  }

  /// Reset all internal state
  void reset() {
    _recentActivity.clear();
    _lastActiveFrame = 0;
    _consecutiveQuietFrames = 0;
    _consecutivePauseFrames = 0;
    _consecutiveZeroEnergyFrames = 0;
    _isInSustainedQuiet = false;
    _lastSubtitleFrame = 0;
    _idleStateStartFrame = 0;
  }

  /// Update speech history with new input
  SpeechHistoryUpdateResult update(SpeechHistoryInput input) {
    final voiceActivity = input.voiceActivity;
    final energy = input.energy;
    final frame = input.frame;

    // Update internal state
    _updateRecentActivity(voiceActivity);
    _updateZeroEnergyCount(energy);
    _updateQuietFrameCount(voiceActivity, frame);
    _updatePauseFrameCount(energy);

    // Build result
    bool shouldFinishSpeaking = false;
    String? finishReason;
    bool shouldMarkPauseExpressionIdle = false;
    bool shouldResumeFromIdle = false;

    // Check finish conditions
    if (_checkSustainedQuiet(frame)) {
      shouldMarkPauseExpressionIdle = true;
      shouldFinishSpeaking = true;
      finishReason = 'sustained_quiet';
    }

    if (_checkZeroEnergyFinish()) {
      shouldMarkPauseExpressionIdle = true;
      shouldFinishSpeaking = true;
      finishReason = 'zero_energy';
    }

    // Check hysteresis recovery
    if (_checkHysteresisRecovery(voiceActivity, energy, frame)) {
      shouldResumeFromIdle = true;
    }

    return SpeechHistoryUpdateResult(
      shouldTriggerPauseCheck: _checkPauseThreshold(),
      shouldFinishSpeaking: shouldFinishSpeaking,
      finishReason: finishReason,
      shouldMarkPauseExpressionIdle: shouldMarkPauseExpressionIdle,
      framesSinceLastSubtitle: frame - _lastSubtitleFrame,
      shouldResumeFromIdle: shouldResumeFromIdle,
    );
  }

  /// Get debug information
  Map<String, dynamic> getDebugInfo() {
    return {
      'recentActivityLength': _recentActivity.length,
      'lastActiveFrame': _lastActiveFrame,
      'consecutiveQuietFrames': _consecutiveQuietFrames,
      'consecutivePauseFrames': _consecutivePauseFrames,
      'consecutiveZeroEnergyFrames': _consecutiveZeroEnergyFrames,
      'isInSustainedQuiet': _isInSustainedQuiet,
      'lastSubtitleFrame': _lastSubtitleFrame,
      'idleStateStartFrame': _idleStateStartFrame,
    };
  }

  // ============================================================================
  // Private Methods - State Updates
  // ============================================================================

  void _updateRecentActivity(VoiceActivityState voiceActivity) {
    _recentActivity.add(voiceActivity);
    if (_recentActivity.length > pauseDetectionConfig.pauseThresholdFrames) {
      _recentActivity.removeAt(0);
    }
  }

  void _updateZeroEnergyCount(double energy) {
    if (energy < _zeroEnergyThreshold) {
      _consecutiveZeroEnergyFrames++;
    } else {
      _consecutiveZeroEnergyFrames = 0;
    }
  }

  void _updateQuietFrameCount(VoiceActivityState voiceActivity, int frame) {
    if (voiceActivity == VoiceActivityState.quiet) {
      _consecutiveQuietFrames++;
    } else {
      _lastActiveFrame = frame;
      _consecutiveQuietFrames = 0;
      _isInSustainedQuiet = false;
    }
  }

  void _updatePauseFrameCount(double energy) {
    final isPause = energy < vadConfig.pauseEnergyThreshold;
    if (isPause) {
      _consecutivePauseFrames++;
    } else {
      _consecutivePauseFrames = 0;
    }
  }

  // ============================================================================
  // Private Methods - Condition Checks
  // ============================================================================

  bool _checkPauseThreshold() {
    return _consecutivePauseFrames ==
        pauseDetectionConfig.pauseThresholdFrames;
  }

  bool _checkSustainedQuiet(int frame) {
    final finishedThresholdFrames =
        pauseDetectionConfig.finishedThresholdFrames;
    final minFramesAfterSubtitle = pauseDetectionConfig.minFramesAfterSubtitle;

    final hasEnoughQuietFrames =
        _consecutiveQuietFrames >= finishedThresholdFrames;
    final notAlreadyInSustainedQuiet = !_isInSustainedQuiet;

    if (!hasEnoughQuietFrames || !notAlreadyInSustainedQuiet) {
      return false;
    }

    final framesSinceSubtitle = frame - _lastSubtitleFrame;
    final subtitleReady =
        framesSinceSubtitle >= minFramesAfterSubtitle || _lastSubtitleFrame == 0;

    if (subtitleReady) {
      _isInSustainedQuiet = true;
      return true;
    }

    return false;
  }

  bool _checkZeroEnergyFinish() {
    final zeroEnergyFrames = pauseDetectionConfig.zeroEnergyFrames;

    if (_consecutiveZeroEnergyFrames >= zeroEnergyFrames) {
      _consecutiveZeroEnergyFrames = 0;
      return true;
    }

    return false;
  }

  bool _checkHysteresisRecovery(
    VoiceActivityState voiceActivity,
    double energy,
    int frame,
  ) {
    if (voiceActivity == VoiceActivityState.quiet || _idleStateStartFrame == 0) {
      return false;
    }

    final framesInIdle = frame - _idleStateStartFrame;
    final hasBeenIdleLongEnough =
        framesInIdle >= pauseDetectionConfig.minIdleDuration;
    final strongSignalThreshold =
        vadConfig.highEnergyThreshold * pauseDetectionConfig.strongSignalMultiplier;
    final hasStrongVoiceSignal = energy > strongSignalThreshold;

    if (hasBeenIdleLongEnough && hasStrongVoiceSignal) {
      debugPrint(
        '[HYSTERESIS] Resume conditions met: $framesInIdle frames in idle, '
        'energy ${energy.toStringAsFixed(6)}',
      );
      return true;
    }

    return false;
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/// Create a SpeechHistoryManager instance
SpeechHistoryManager createSpeechHistoryManager(
  VadConfig vadConfig,
  PauseDetectionConfig pauseDetectionConfig,
) {
  return SpeechHistoryManager(
    vadConfig: vadConfig,
    pauseDetectionConfig: pauseDetectionConfig,
  );
}
