// Audio Configuration
//
// Centralized configuration for audio processing, voice activity detection,
// and pause detection.

import '../modules/types.dart';

export '../modules/types.dart' show VadConfig, PauseDetectionConfig;

/// Audio Analysis Configuration
///
/// Controls audio API parameters for audio analysis.
class AudioAnalysisConfig {
  /// FFT size for frequency analysis (power of 2, typically 2048)
  final int fftSize;

  /// Smoothing time constant for frequency data (0-1)
  final double smoothingTimeConstant;

  /// High frequency band start position (0-1, as fraction of frequency bins)
  final double highFreqBandStart;

  const AudioAnalysisConfig({
    required this.fftSize,
    required this.smoothingTimeConstant,
    required this.highFreqBandStart,
  });
}

/// Default Audio Analysis Configuration
const defaultAudioAnalysisConfig = AudioAnalysisConfig(
  fftSize: 2048, // Standard FFT size for analysis
  smoothingTimeConstant: 0.8, // Smooth frequency changes
  highFreqBandStart: 0.6, // High frequency starts at 60% of frequency range
);

/// Default VAD Configuration
///
/// NOTE: These values are optimized for real-time voice conversation.
const defaultVadConfig = VadConfig(
  // Audio energy thresholds
  lowEnergyThreshold: 0.002,
  highEnergyThreshold: 0.012,
  pauseEnergyThreshold: 0.004,

  // Audio analysis parameters
  zcrWeight: 0.3,
  smoothingFactor: 0.6,
  debounceFrames: 3,
);

/// Default Pause Detection Configuration
const defaultPauseDetectionConfig = PauseDetectionConfig(
  pauseThresholdFrames: 7, // 0.3s pause detection (7 frames @ 24fps)
  finishedThresholdFrames: 36, // 1.5s sustained quiet (36 frames @ 24fps)
  zeroEnergyFrames: 24, // 1.0s zero energy (24 frames @ 24fps)

  // Additional constants
  minFramesAfterSubtitle: 72, // 3.0s after subtitle (72 frames @ 24fps)
  minIdleDuration: 12, // 0.5s minimum idle for recovery (12 frames @ 24fps)
  strongSignalMultiplier:
      0.5, // 50% of highEnergyThreshold for strong signal (0.012 * 0.5 = 0.006)
);
