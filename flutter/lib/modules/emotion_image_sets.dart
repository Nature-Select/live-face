// Emotion Image Set Management
//
// 管理情绪图像集的存储和访问
// 每个情绪对应4张图像，覆盖所有眼睛/嘴巴状态组合

import 'package:flutter/foundation.dart';

/// 情绪图像集（4张图像覆盖所有眼睛/嘴巴状态组合）
class EmotionImageSet {
  /// 闭眼闭嘴
  final String eyesClosedMouthClosed;

  /// 睁眼闭嘴
  final String eyesOpenMouthClosed;

  /// 闭眼张嘴
  final String eyesClosedMouthOpen;

  /// 睁眼张嘴
  final String eyesOpenMouthOpen;

  const EmotionImageSet({
    required this.eyesClosedMouthClosed,
    required this.eyesOpenMouthClosed,
    required this.eyesClosedMouthOpen,
    required this.eyesOpenMouthOpen,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is EmotionImageSet &&
        other.eyesClosedMouthClosed == eyesClosedMouthClosed &&
        other.eyesOpenMouthClosed == eyesOpenMouthClosed &&
        other.eyesClosedMouthOpen == eyesClosedMouthOpen &&
        other.eyesOpenMouthOpen == eyesOpenMouthOpen;
  }

  @override
  int get hashCode {
    return Object.hash(
      eyesClosedMouthClosed,
      eyesOpenMouthClosed,
      eyesClosedMouthOpen,
      eyesOpenMouthOpen,
    );
  }
}

/// Emotion Image Sets Manager
///
/// Manages the storage and access of emotion image sets.
/// This is a global singleton to maintain state across the app.
class EmotionImageSetsManager {
  EmotionImageSetsManager._();

  static final EmotionImageSetsManager _instance =
      EmotionImageSetsManager._();

  static EmotionImageSetsManager get instance => _instance;

  /// 内部情绪图像集存储
  /// Key: 情绪标签（如 '[calm]', '[happy]'）
  /// Value: 对应的4张图像
  final Map<String, EmotionImageSet> _emotionImageSets = {};

  /// 获取情绪图像集
  /// @param emotion - 情绪标签
  /// @returns 图像集或 null（如果情绪不存在）
  EmotionImageSet? getEmotionImageSet(String emotion) {
    final imageSet = _emotionImageSets[emotion];
    if (imageSet == null) {
      if (_emotionImageSets.isNotEmpty) {
        debugPrint("[IMAGE SETS] Emotion '$emotion' not found");
      }
      return null;
    }
    return imageSet;
  }

  /// 批量设置情绪图像集（会合并到现有集合）
  /// @param newSets - 新的图像集
  void setEmotionImageSets(Map<String, EmotionImageSet> newSets) {
    _emotionImageSets.addAll(newSets);
    debugPrint('[IMAGE SETS] Updated: ${_emotionImageSets.keys.join(', ')}');
  }

  /// 获取所有情绪图像集（只读）
  /// @returns 当前所有图像集的只读副本
  Map<String, EmotionImageSet> getAllEmotionImageSets() {
    return Map.unmodifiable(_emotionImageSets);
  }

  /// 获取已注册的情绪列表
  /// @returns 情绪标签数组
  List<String> getRegisteredEmotions() {
    return _emotionImageSets.keys.toList();
  }

  /// 清空所有图像集（用于测试）
  void clear() {
    _emotionImageSets.clear();
  }
}

// Global convenience functions for backwards compatibility

/// 获取情绪图像集
EmotionImageSet? getEmotionImageSet(String emotion) {
  return EmotionImageSetsManager.instance.getEmotionImageSet(emotion);
}

/// 批量设置情绪图像集
void setEmotionImageSets(Map<String, EmotionImageSet> newSets) {
  EmotionImageSetsManager.instance.setEmotionImageSets(newSets);
}

/// 获取所有情绪图像集
Map<String, EmotionImageSet> getAllEmotionImageSets() {
  return EmotionImageSetsManager.instance.getAllEmotionImageSets();
}

/// 获取已注册的情绪列表
List<String> getRegisteredEmotions() {
  return EmotionImageSetsManager.instance.getRegisteredEmotions();
}
