// Audio Analysis
//
// Provides audio feature extraction for voice activity detection.
// Adapted from Web Audio API to work with Agora Flutter SDK.

import '../config/audio_config.dart';

/// Voice metrics extracted from audio
class VoiceMetrics {
  /// RMS energy of the audio signal
  final double energy;

  /// Zero crossing rate
  final double zcr;

  /// Spectral centroid (frequency center of mass)
  final double spectralCentroid;

  /// High frequency energy ratio
  final double highFreqEnergy;

  const VoiceMetrics({
    required this.energy,
    required this.zcr,
    required this.spectralCentroid,
    required this.highFreqEnergy,
  });

  /// Zero metrics (no audio)
  static const zero = VoiceMetrics(
    energy: 0,
    zcr: 0,
    spectralCentroid: 0,
    highFreqEnergy: 0,
  );

  /// Create metrics from Agora volume indication
  ///
  /// When using Agora's onAudioVolumeIndication, we only have volume data.
  /// We simulate other metrics based on volume for compatibility.
  factory VoiceMetrics.fromAgoraVolume(int volume) {
    // Agora volume is 0-255, normalize to 0-1
    final normalizedVolume = volume / 255.0;

    // Energy is proportional to volume squared
    final energy = normalizedVolume * normalizedVolume;

    // Simulate ZCR - higher volume often correlates with more voice activity
    final zcr = normalizedVolume * 0.1;

    // Simulate spectral centroid - higher for voice
    final spectralCentroid = normalizedVolume > 0.1 ? 500.0 : 0.0;

    // Simulate high freq energy - proportional to volume
    final highFreqEnergy = normalizedVolume * 0.5;

    return VoiceMetrics(
      energy: energy,
      zcr: zcr,
      spectralCentroid: spectralCentroid,
      highFreqEnergy: highFreqEnergy,
    );
  }

  /// Create metrics from raw audio samples
  ///
  /// This can be used if you have access to raw audio data from
  /// Agora's AudioFrameObserver.
  factory VoiceMetrics.fromSamples(
    List<double> samples, {
    AudioAnalysisConfig config = defaultAudioAnalysisConfig,
  }) {
    if (samples.isEmpty) {
      return VoiceMetrics.zero;
    }

    final bufferLength = samples.length;

    // Calculate RMS energy
    double energy = 0;
    for (int i = 0; i < bufferLength; i++) {
      energy += samples[i] * samples[i];
    }
    energy = energy / bufferLength;

    // Calculate Zero Crossing Rate
    int zcrCount = 0;
    for (int i = 1; i < bufferLength; i++) {
      if ((samples[i] >= 0) != (samples[i - 1] >= 0)) {
        zcrCount++;
      }
    }
    final zcr = zcrCount / (2 * bufferLength);

    // For spectralCentroid and highFreqEnergy, we would need FFT
    // For now, return simplified values based on energy
    final spectralCentroid = energy > 0.001 ? 500.0 : 0.0;
    final highFreqEnergy = energy * 0.5;

    return VoiceMetrics(
      energy: energy,
      zcr: zcr,
      spectralCentroid: spectralCentroid,
      highFreqEnergy: highFreqEnergy,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is VoiceMetrics &&
        other.energy == energy &&
        other.zcr == zcr &&
        other.spectralCentroid == spectralCentroid &&
        other.highFreqEnergy == highFreqEnergy;
  }

  @override
  int get hashCode {
    return Object.hash(energy, zcr, spectralCentroid, highFreqEnergy);
  }

  @override
  String toString() {
    return 'VoiceMetrics(energy: ${energy.toStringAsFixed(4)}, '
        'zcr: ${zcr.toStringAsFixed(4)}, '
        'spectralCentroid: ${spectralCentroid.toStringAsFixed(2)}, '
        'highFreqEnergy: ${highFreqEnergy.toStringAsFixed(4)})';
  }
}

/// Audio analyzer for extracting voice metrics
///
/// This class provides a simplified interface for audio analysis.
/// In a real implementation, you would integrate with Agora's audio callbacks.
class AudioAnalyzer {
  final AudioAnalysisConfig config;

  // Smoothed metrics for temporal consistency
  VoiceMetrics _smoothedMetrics = VoiceMetrics.zero;

  AudioAnalyzer({this.config = defaultAudioAnalysisConfig});

  /// Update metrics from Agora volume indication
  ///
  /// Call this from Agora's onAudioVolumeIndication callback.
  VoiceMetrics updateFromVolume(int volume) {
    final newMetrics = VoiceMetrics.fromAgoraVolume(volume);
    _smoothedMetrics = _smoothMetrics(newMetrics);
    return _smoothedMetrics;
  }

  /// Update metrics from raw audio samples
  ///
  /// Call this from Agora's AudioFrameObserver if available.
  VoiceMetrics updateFromSamples(List<double> samples) {
    final newMetrics = VoiceMetrics.fromSamples(samples, config: config);
    _smoothedMetrics = _smoothMetrics(newMetrics);
    return _smoothedMetrics;
  }

  /// Get current smoothed metrics
  VoiceMetrics get currentMetrics => _smoothedMetrics;

  /// Reset analyzer state
  void reset() {
    _smoothedMetrics = VoiceMetrics.zero;
  }

  /// Apply temporal smoothing to metrics
  VoiceMetrics _smoothMetrics(VoiceMetrics newMetrics) {
    final smoothing = config.smoothingTimeConstant;
    final oneMinusSmoothing = 1 - smoothing;

    return VoiceMetrics(
      energy: _smoothedMetrics.energy * smoothing +
          newMetrics.energy * oneMinusSmoothing,
      zcr:
          _smoothedMetrics.zcr * smoothing + newMetrics.zcr * oneMinusSmoothing,
      spectralCentroid: _smoothedMetrics.spectralCentroid * smoothing +
          newMetrics.spectralCentroid * oneMinusSmoothing,
      highFreqEnergy: _smoothedMetrics.highFreqEnergy * smoothing +
          newMetrics.highFreqEnergy * oneMinusSmoothing,
    );
  }
}

/// Helper function to convert PCM16 audio data to normalized samples
List<double> convertPcm16ToSamples(List<int> pcm16Data) {
  return pcm16Data.map((sample) => sample / 32768.0).toList();
}

/// Helper function to calculate RMS energy from volume level
double volumeToEnergy(int volume) {
  final normalized = volume / 255.0;
  return normalized * normalized;
}
