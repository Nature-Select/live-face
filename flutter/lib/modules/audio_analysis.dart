// Audio Analysis
//
// Provides audio feature extraction for voice activity detection.
// Adapted from Web Audio API to work with Agora Flutter SDK.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fftea/fftea.dart';

import '../config/audio_config.dart';

// Web Audio API AnalyserNode 默认参数
const double _minDecibels = -100.0;
const double _maxDecibels = -30.0;

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

    // 1. Calculate RMS energy
    double energy = 0;
    for (int i = 0; i < bufferLength; i++) {
      energy += samples[i] * samples[i];
    }
    energy = energy / bufferLength;

    // 2. Calculate Zero Crossing Rate
    int zcrCount = 0;
    for (int i = 1; i < bufferLength; i++) {
      if ((samples[i] >= 0) != (samples[i - 1] >= 0)) {
        zcrCount++;
      }
    }
    final zcr = zcrCount / (2 * bufferLength);

    // 3. Perform FFT analysis for spectral features
    final fft = FFT(bufferLength);
    final samplesFloat64 = Float64List.fromList(samples);
    final freqDomain = fft.realFft(samplesFloat64);
    final rawMagnitudes = freqDomain.discardConjugates().magnitudes();

    // Convert to Web Audio API style byte frequency data (0-255)
    // This matches AnalyserNode.getByteFrequencyData() behavior
    final frequencyData = _convertToByteFrequencyData(rawMagnitudes);

    // 4. Calculate Spectral Centroid (frequency center of mass)
    // Same as Web: frequencyData[i] / 255.0
    double weightedSum = 0;
    double magnitudeSum = 0;
    for (int i = 0; i < frequencyData.length; i++) {
      final magnitude = frequencyData[i] / 255.0;
      weightedSum += i * magnitude;
      magnitudeSum += magnitude;
    }
    final spectralCentroid = magnitudeSum > 0 ? weightedSum / magnitudeSum : 0.0;

    // 5. Calculate High Frequency Energy (60% and above)
    // Same as Web: (frequencyData[i] / 255.0) ** 2
    final highFreqStart = (frequencyData.length * config.highFreqBandStart).floor();
    double highFreqEnergy = 0;
    for (int i = highFreqStart; i < frequencyData.length; i++) {
      final normalized = frequencyData[i] / 255.0;
      highFreqEnergy += normalized * normalized;
    }
    highFreqEnergy =
        highFreqEnergy / math.max(1, frequencyData.length - highFreqStart);

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

/// Audio analyzer that simulates Web Audio API AnalyserNode behavior
///
/// Key features matching Web Audio API:
/// 1. Sliding window buffer - maintains continuous audio data with overlap
/// 2. Frequency domain smoothing - applies smoothingTimeConstant to frequency bins
///
/// This provides smooth, continuous metrics similar to the Web implementation.
class AudioAnalyzer {
  final AudioAnalysisConfig config;

  /// Sliding window buffer - simulates AnalyserNode's internal buffer
  /// Web Audio API maintains a buffer that continuously updates with new samples
  /// We maintain a larger buffer and take the latest fftSize samples for analysis
  late final List<double> _slidingBuffer;

  /// Current write position in the sliding buffer
  int _bufferWritePos = 0;

  /// Whether the buffer has been filled at least once
  bool _bufferFilled = false;

  /// Previous frame's frequency data for smoothing
  /// Web Audio API applies smoothingTimeConstant to each frequency bin independently
  List<double>? _previousFrequencyData;

  AudioAnalyzer({this.config = defaultAudioAnalysisConfig}) {
    // Initialize sliding buffer (2x fftSize to allow continuous writing)
    _slidingBuffer = List<double>.filled(config.fftSize * 2, 0.0);
  }

  /// Append new audio samples to the sliding buffer
  ///
  /// Call this from Agora's AudioFrameObserver callback.
  /// The samples are added to the sliding buffer for later analysis.
  void appendSamples(List<double> samples) {
    for (final sample in samples) {
      _slidingBuffer[_bufferWritePos] = sample;
      _bufferWritePos = (_bufferWritePos + 1) % _slidingBuffer.length;
      if (_bufferWritePos == 0) {
        _bufferFilled = true;
      }
    }
  }

  /// Analyze current buffer and return voice metrics
  ///
  /// Call this at a fixed rate (e.g., 24fps) to get consistent metrics.
  /// This simulates Web Audio API's behavior where you call getFloatTimeDomainData()
  /// at any time to get the current buffer contents.
  VoiceMetrics analyze() {
    // Get the latest fftSize samples from the sliding buffer
    final samples = _getLatestSamples(config.fftSize);

    if (samples.isEmpty) {
      return VoiceMetrics.zero;
    }

    final bufferLength = samples.length;

    // 1. Calculate RMS energy (time domain)
    double energy = 0;
    for (int i = 0; i < bufferLength; i++) {
      energy += samples[i] * samples[i];
    }
    energy = energy / bufferLength;

    // 2. Calculate Zero Crossing Rate (time domain)
    int zcrCount = 0;
    for (int i = 1; i < bufferLength; i++) {
      if ((samples[i] >= 0) != (samples[i - 1] >= 0)) {
        zcrCount++;
      }
    }
    final zcr = zcrCount / (2 * bufferLength);

    // 3. Perform FFT for frequency domain analysis
    final fft = FFT(bufferLength);
    final samplesFloat64 = Float64List.fromList(samples);
    final freqDomain = fft.realFft(samplesFloat64);
    final rawMagnitudes = freqDomain.discardConjugates().magnitudes();

    // 4. Apply frequency domain smoothing (key difference from before!)
    // Web Audio API: currentValue = smoothing * previousValue + (1-smoothing) * newValue
    final smoothedMagnitudes = _applySmoothingToFrequencyData(rawMagnitudes);

    // 5. Convert to byte frequency data (0-255) like Web Audio API
    final frequencyData = _convertMagnitudesToByteData(smoothedMagnitudes);

    // 6. Calculate Spectral Centroid from smoothed frequency data
    double weightedSum = 0;
    double magnitudeSum = 0;
    for (int i = 0; i < frequencyData.length; i++) {
      final magnitude = frequencyData[i] / 255.0;
      weightedSum += i * magnitude;
      magnitudeSum += magnitude;
    }
    final spectralCentroid =
        magnitudeSum > 0 ? weightedSum / magnitudeSum : 0.0;

    // 7. Calculate High Frequency Energy from smoothed frequency data
    final highFreqStart =
        (frequencyData.length * config.highFreqBandStart).floor();
    double highFreqEnergy = 0;
    for (int i = highFreqStart; i < frequencyData.length; i++) {
      final normalized = frequencyData[i] / 255.0;
      highFreqEnergy += normalized * normalized;
    }
    highFreqEnergy =
        highFreqEnergy / math.max(1, frequencyData.length - highFreqStart);

    return VoiceMetrics(
      energy: energy,
      zcr: zcr,
      spectralCentroid: spectralCentroid,
      highFreqEnergy: highFreqEnergy,
    );
  }

  /// Get the latest N samples from the sliding buffer
  List<double> _getLatestSamples(int count) {
    if (!_bufferFilled && _bufferWritePos < count) {
      // Not enough samples yet
      if (_bufferWritePos == 0) return [];
      // Return what we have
      return _slidingBuffer.sublist(0, _bufferWritePos);
    }

    final result = List<double>.filled(count, 0.0);
    int readPos = (_bufferWritePos - count + _slidingBuffer.length) %
        _slidingBuffer.length;

    for (int i = 0; i < count; i++) {
      result[i] = _slidingBuffer[readPos];
      readPos = (readPos + 1) % _slidingBuffer.length;
    }

    return result;
  }

  /// Apply smoothingTimeConstant to frequency data
  /// This is the KEY behavior of Web Audio API AnalyserNode
  Float64List _applySmoothingToFrequencyData(Float64List currentMagnitudes) {
    final smoothing = config.smoothingTimeConstant;
    final oneMinusSmoothing = 1 - smoothing;

    if (_previousFrequencyData == null ||
        _previousFrequencyData!.length != currentMagnitudes.length) {
      // First frame or size changed - no smoothing possible
      _previousFrequencyData = List<double>.from(currentMagnitudes);
      return currentMagnitudes;
    }

    // Apply smoothing to each frequency bin independently
    // Formula: smoothedValue = smoothing * previousValue + (1-smoothing) * currentValue
    final smoothed = Float64List(currentMagnitudes.length);
    for (int i = 0; i < currentMagnitudes.length; i++) {
      smoothed[i] = smoothing * _previousFrequencyData![i] +
          oneMinusSmoothing * currentMagnitudes[i];
    }

    // Save for next frame
    _previousFrequencyData = List<double>.from(smoothed);

    return smoothed;
  }

  /// Convert smoothed magnitudes to byte data (0-255)
  List<int> _convertMagnitudesToByteData(Float64List magnitudes) {
    final result = List<int>.filled(magnitudes.length, 0);
    final rangeScaleFactor = 255.0 / (_maxDecibels - _minDecibels);

    for (int i = 0; i < magnitudes.length; i++) {
      final magnitude = magnitudes[i];

      double dB;
      if (magnitude < 1e-10) {
        dB = _minDecibels;
      } else {
        dB = 20.0 * math.log(magnitude) / math.ln10;
      }

      final byteValue = ((dB - _minDecibels) * rangeScaleFactor).round();
      result[i] = byteValue.clamp(0, 255);
    }

    return result;
  }

  /// Legacy method for compatibility - appends samples and analyzes
  VoiceMetrics updateFromSamples(List<double> samples) {
    appendSamples(samples);
    return analyze();
  }

  /// Update metrics from Agora volume indication (fallback when no raw audio)
  VoiceMetrics updateFromVolume(int volume) {
    return VoiceMetrics.fromAgoraVolume(volume);
  }

  /// Get current metrics (call analyze() for fresh data)
  VoiceMetrics get currentMetrics => analyze();

  /// Reset analyzer state
  void reset() {
    _slidingBuffer.fillRange(0, _slidingBuffer.length, 0.0);
    _bufferWritePos = 0;
    _bufferFilled = false;
    _previousFrequencyData = null;
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

/// Convert raw FFT magnitudes to Web Audio API style byte frequency data (0-255)
///
/// This simulates the behavior of AnalyserNode.getByteFrequencyData() which:
/// 1. Converts magnitude to decibels: dB = 20 * log10(magnitude)
/// 2. Maps dB range [minDecibels, maxDecibels] to [0, 255]
///
/// Default values match Web Audio API: minDecibels = -100, maxDecibels = -30
List<int> _convertToByteFrequencyData(Float64List magnitudes) {
  final result = List<int>.filled(magnitudes.length, 0);
  final rangeScaleFactor = 255.0 / (_maxDecibels - _minDecibels);

  for (int i = 0; i < magnitudes.length; i++) {
    final magnitude = magnitudes[i];

    // Avoid log(0) - use a very small value
    double dB;
    if (magnitude < 1e-10) {
      dB = _minDecibels;
    } else {
      dB = 20.0 * math.log(magnitude) / math.ln10; // log10(x) = ln(x) / ln(10)
    }

    // Map dB to 0-255 range (same as Web Audio API)
    final byteValue = ((dB - _minDecibels) * rangeScaleFactor).round();
    result[i] = byteValue.clamp(0, 255);
  }

  return result;
}
