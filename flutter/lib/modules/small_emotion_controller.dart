// Small Emotion Controller
//
// Manages PAG animations for small emotion expressions.

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../config/small_emotion_config.dart';

// ============================================================================
// Types
// ============================================================================

/// PAG animation configuration
class PAGAnimationConfig {
  final String src;
  final double weight;

  const PAGAnimationConfig({
    required this.src,
    required this.weight,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PAGAnimationConfig &&
        other.src == src &&
        other.weight == weight;
  }

  @override
  int get hashCode => Object.hash(src, weight);
}

/// Emotion PAG configuration
class EmotionPAGConfig {
  final List<PAGAnimationConfig> animations;
  final double? customEmptyWeight;

  const EmotionPAGConfig({
    required this.animations,
    this.customEmptyWeight,
  });
}

// ============================================================================
// SmallEmotionManager Class
// ============================================================================

/// Manages PAG animations for small emotion expressions
class SmallEmotionManager {
  // Internal State
  double _emptyWeight = defaultEmptyWeight.toDouble();
  final Map<String, EmotionPAGConfig> _emotionPAGMap = {};
  final Random _random = Random();

  SmallEmotionManager();

  // ============================================================================
  // Public Methods - Core
  // ============================================================================

  /// Weighted random selection of PAG animation
  PAGAnimationConfig? selectRandomPAG(String emotion) {
    final config = _emotionPAGMap[emotion];
    if (config == null) {
      return null;
    }

    final effectiveEmptyWeight = config.customEmptyWeight ?? _emptyWeight;
    final totalWeight = effectiveEmptyWeight + _calculateAnimationWeight(config);
    final randomValue = _random.nextDouble() * totalWeight;

    if (randomValue < effectiveEmptyWeight) {
      return null;
    }

    return _selectByWeight(config.animations, effectiveEmptyWeight, randomValue);
  }

  // ============================================================================
  // Public Methods - Configuration
  // ============================================================================

  /// Set PAG animation map (called during initialization)
  void setPAGMap(Map<String, List<String>> newMap) {
    for (final entry in newMap.entries) {
      final emotionTag = entry.key;
      final urls = entry.value;
      _emotionPAGMap[emotionTag] = EmotionPAGConfig(
        animations: urls
            .map((url) => PAGAnimationConfig(
                  src: url,
                  weight: animationWeight.toDouble(),
                ))
            .toList(),
      );
    }
  }

  /// Set empty weight (for debugging)
  void setEmptyWeight(double value) {
    _emptyWeight = value.clamp(0, 10);
    debugPrint('[Small Emotion] EMPTY_WEIGHT updated to: $_emptyWeight');
  }

  /// Get debug information
  Map<String, dynamic> getDebugInfo() {
    return {
      'emptyWeight': _emptyWeight,
      'registeredEmotions': _emotionPAGMap.keys.toList(),
      'emotionCount': _emotionPAGMap.length,
      'animationCounts': Map.fromEntries(
        _emotionPAGMap.entries.map(
          (e) => MapEntry(e.key, e.value.animations.length),
        ),
      ),
    };
  }

  /// Clear all PAG configurations (for testing)
  void clear() {
    _emotionPAGMap.clear();
    _emptyWeight = defaultEmptyWeight.toDouble();
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  double _calculateAnimationWeight(EmotionPAGConfig config) {
    return config.animations.fold(0.0, (sum, anim) => sum + anim.weight);
  }

  PAGAnimationConfig _selectByWeight(
    List<PAGAnimationConfig> animations,
    double emptyWeight,
    double randomValue,
  ) {
    double cumulativeWeight = emptyWeight;

    for (final animation in animations) {
      cumulativeWeight += animation.weight;
      if (randomValue < cumulativeWeight) {
        return animation;
      }
    }

    return animations.last;
  }
}

// ============================================================================
// Factory Function
// ============================================================================

/// Create a SmallEmotionManager instance
SmallEmotionManager createSmallEmotionManager() {
  return SmallEmotionManager();
}

// ============================================================================
// Global Singleton (for resource initialization)
// ============================================================================

final SmallEmotionManager globalSmallEmotionManager = SmallEmotionManager();

// Convenience functions for global singleton

/// Set PAG animation map
void setPAGMap(Map<String, List<String>> newMap) {
  globalSmallEmotionManager.setPAGMap(newMap);
}

/// Select random PAG animation
PAGAnimationConfig? selectRandomPAG(String emotion) {
  return globalSmallEmotionManager.selectRandomPAG(emotion);
}

/// Set empty weight
void setEmptyWeight(double value) {
  globalSmallEmotionManager.setEmptyWeight(value);
}

/// Get debug information
Map<String, dynamic> getSmallEmotionDebugInfo() {
  return globalSmallEmotionManager.getDebugInfo();
}
