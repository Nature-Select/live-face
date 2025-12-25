/// Frame Selector - Unified Animation Frame Selection
///
/// 统一的帧选择器，封装所有动画状态更新逻辑。
///
/// 核心理念：
/// 1. 纯函数处理每一帧的数据
/// 2. 不依赖外部状态机，而是推导出当前应该处于的状态
/// 3. 调用方负责协调状态机事件触发
library;

import 'package:flutter/foundation.dart';

import '../config/eyes_config.dart';
import '../config/mouth_config.dart';
import 'audio_analysis.dart';
import 'emotion_image_sets.dart';
import 'eyes_controller.dart';
import 'mouth_controller.dart';
import 'small_emotion_controller.dart';
import 'speech_history.dart';
import 'types.dart';
import 'vad.dart';

// ============================================================================
// Types
// ============================================================================

/// 当前消息数据（包含所有元数据）
class CurrentMessage {
  final String id;
  final String content;
  final String? emotion;
  final String? emoji;
  final int? turnId;
  final int? turnStatus;

  const CurrentMessage({
    required this.id,
    required this.content,
    this.emotion,
    this.emoji,
    this.turnId,
    this.turnStatus,
  });
}

/// 输入数据 - 每一帧的原始数据
class FrameInput {
  /// 音频特征（来自 AudioAnalyzer）
  final VoiceMetrics audioMetrics;

  /// 当前未显示的消息（包含所有元数据）
  final CurrentMessage? currentMessage;

  /// 当前帧编号
  final int frameNumber;

  const FrameInput({
    required this.audioMetrics,
    this.currentMessage,
    required this.frameNumber,
  });
}

/// 调试信息
class FrameDebugInfo {
  final MouthIntensity mouthState;
  final EyesState eyesState;
  final VoiceActivityState voiceActivity;
  final double energy;

  const FrameDebugInfo({
    required this.mouthState,
    required this.eyesState,
    required this.voiceActivity,
    required this.energy,
  });
}

/// 输出数据 - 渲染所需的所有信息
class FrameOutput {
  /// 角色图片 URL
  final String imageUrl;

  /// PAG 动画 src（直接返回 String?）
  final String? pag;

  /// Emoji URL（用于 emoji overlay 显示）
  final String? emoji;

  /// 检测到的会话状态（推导结果）
  final ActorState detectedState;

  /// 是否显示新字幕
  final bool shouldDisplaySubtitle;

  /// 应该显示的消息 ID
  final String? messageIdToDisplay;

  /// 调试信息
  final FrameDebugInfo? debug;

  const FrameOutput({
    required this.imageUrl,
    this.pag,
    this.emoji,
    required this.detectedState,
    required this.shouldDisplaySubtitle,
    this.messageIdToDisplay,
    this.debug,
  });
}

// ============================================================================
// Frame Selector Class
// ============================================================================

/// Unified frame selector that coordinates all animation subsystems
class FrameSelector {
  final VadConfig vadConfig;
  final PauseDetectionConfig pauseDetectionConfig;

  // Internal Controllers
  late final MouthController _mouthController;
  late final EyesStateManager _eyesStateManager;
  late final VoiceActivityManager _voiceActivityManager;
  late final SpeechHistoryManager _speechHistoryManager;

  // Internal State
  ActorState _currentDetectedState = ActorState.idle;
  // Emotion used for rendering frames (only update when SPEAKING starts)
  String _currentRenderedEmotion = '[peace]';

  // PAG Animation State
  String? _pagSrc;

  // Emoji State
  String? _currentEmoji;
  int? _lastEmotionTriggeredTurnId;

  // Pending emotion trigger (for delayed triggering)
  ({String emotion, String? emoji})? _pendingEmotionTrigger;

  FrameSelector({
    required this.vadConfig,
    required this.pauseDetectionConfig,
    EyesLifecycleConfig? eyesLifecycleConfig,
    EyesTimingConfig? eyesTimingConfig,
    MouthConfig? mouthConfig,
  }) {
    // Initialize controllers with lifecycle state callback
    _mouthController = MouthController(
      getLifecycleState: () => _currentDetectedState,
      vadConfig: vadConfig,
      mouthConfig: mouthConfig,
    );

    _voiceActivityManager = VoiceActivityManager(
      VoiceActivityManagerConfig(
        debounceFrames: vadConfig.debounceFrames,
        smoothingFactor: vadConfig.smoothingFactor,
      ),
      VoiceActivityState.quiet,
    );

    _eyesStateManager = EyesStateManager(
      getLifecycleState: () => _currentDetectedState,
      lifecycleConfig: eyesLifecycleConfig,
      timingConfig: eyesTimingConfig,
    );

    _speechHistoryManager = SpeechHistoryManager(
      vadConfig: vadConfig,
      pauseDetectionConfig: pauseDetectionConfig,
    );
  }

  /// Select animation frame based on emotion, mouth state, and eyes state (pure method)
  String _selectFrame(
    String emotion,
    MouthIntensity mouthState,
    EyesState eyesState,
  ) {
    // 1. Get emotion image set with fallback to [peace]
    var imageSet = getEmotionImageSet(emotion);
    if (imageSet == null) {
      debugPrint("[ANIMATION] Emotion '$emotion' not found, falling back to [peace]");
      imageSet = getEmotionImageSet('[peace]');
      if (imageSet == null) {
        throw Exception(
          "[ANIMATION] Critical: Default emotion '[peace]' not found - backend data integrity error",
        );
      }
    }

    // 2. Select image based on eyes and mouth state
    final eyesClosed = eyesState == EyesState.closed;
    final mouthClosed = mouthState == MouthIntensity.closed;

    if (eyesClosed && !mouthClosed) {
      return imageSet.eyesClosedMouthOpen;
    } else if (eyesClosed && mouthClosed) {
      return imageSet.eyesClosedMouthClosed;
    } else if (!eyesClosed && !mouthClosed) {
      return imageSet.eyesOpenMouthOpen;
    } else {
      return imageSet.eyesOpenMouthClosed;
    }
  }

  /// Process a single frame and return rendering output
  FrameOutput processFrame(FrameInput input) {
    final audioMetrics = input.audioMetrics;
    final currentMessage = input.currentMessage;
    final frameNumber = input.frameNumber;

    final energy = audioMetrics.energy;
    final zcr = audioMetrics.zcr;

    // Incoming emotion from latest message (do NOT render immediately; wait until SPEAKING starts)
    final incomingEmotion = currentMessage?.emotion ?? '[peace]';

    // 1. Voice activity detection
    final newVoiceActivity = classifyVoiceActivity(energy, zcr, vadConfig);
    final smoothedActivity = _voiceActivityManager.smooth(newVoiceActivity);

    // 2. 处理 turnStatus === 1（情绪触发）
    final turnStatus = currentMessage?.turnStatus ?? 0;
    final turnId = currentMessage?.turnId;

    // Use turnId-based dedupe (instead of 0→1 edge) to avoid missing triggers
    final shouldTriggerForThisTurn =
        turnStatus == 1 && turnId != null && turnId != _lastEmotionTriggeredTurnId;

    if (shouldTriggerForThisTurn) {
      final emotion = incomingEmotion;
      final emoji = currentMessage?.emoji;

      if (_currentDetectedState == ActorState.speaking) {
        // 已在 SPEAKING 状态 → 立即触发
        _triggerEmotionAnimation(emotion, emoji);
        debugPrint('✅ [EMOTION] Triggered immediately (already SPEAKING)');
      } else {
        // 还在 IDLE 状态 → 暂存，等 SPEAKING 开始时触发
        _pendingEmotionTrigger = (emotion: emotion, emoji: emoji);
        debugPrint('⏳ [EMOTION] Queued for SPEAKING start');
      }

      _lastEmotionTriggeredTurnId = turnId;
    }

    // 3. 字幕显示判断 + 状态转换 + 触发 pending
    bool shouldDisplaySubtitle = false;
    String? messageIdToDisplay;

    if (currentMessage != null && newVoiceActivity == VoiceActivityState.active) {
      shouldDisplaySubtitle = true;
      messageIdToDisplay = currentMessage.id;
      _speechHistoryManager.recordSubtitleFrame(frameNumber);

      // 状态转换：IDLE → SPEAKING
      final wasIdle = _currentDetectedState == ActorState.idle;
      _currentDetectedState = ActorState.speaking;
      _speechHistoryManager.reset();

      // Only update rendered emotion when we actually start SPEAKING / display subtitle
      _currentRenderedEmotion = incomingEmotion;

      // 检测 SPEAKING 开始，触发 pending 的情绪动画
      if (wasIdle && _pendingEmotionTrigger != null) {
        _triggerEmotionAnimation(
          _pendingEmotionTrigger!.emotion,
          _pendingEmotionTrigger!.emoji,
        );
        _pendingEmotionTrigger = null;
        debugPrint('✅ [EMOTION] Triggered at SPEAKING start');
      }
    }

    // 4. Speech history update (finish detection)
    final speechHistoryResult = _speechHistoryManager.update(
      SpeechHistoryInput(
        voiceActivity: smoothedActivity,
        energy: energy,
        frame: frameNumber,
      ),
    );

    // 仅在"确实进入过 SPEAKING"时才允许 finish 生效
    if (_currentDetectedState == ActorState.speaking &&
        speechHistoryResult.shouldFinishSpeaking) {
      debugPrint('[SUBTITLE] shouldFinishSpeaking');
      _currentDetectedState = ActorState.idle;
      _pendingEmotionTrigger = null; // 清空 pending
      _currentEmoji = null;
    }

    // 5. Eyes & mouth state
    final eyesState = _eyesStateManager.update();
    final mouthState = _mouthController.update(
      AudioFeatureSet(
        energy: energy,
        zcr: zcr,
        spectralCentroid: audioMetrics.spectralCentroid,
        highFreqEnergy: audioMetrics.highFreqEnergy,
      ),
    );

    // 6. Select frame (emotion only updates when SPEAKING starts)
    final imageUrl = _selectFrame(_currentRenderedEmotion, mouthState, eyesState);

    return FrameOutput(
      imageUrl: imageUrl,
      pag: _pagSrc,
      emoji: _currentEmoji,
      detectedState: _currentDetectedState,
      shouldDisplaySubtitle: shouldDisplaySubtitle,
      messageIdToDisplay: messageIdToDisplay,
      debug: FrameDebugInfo(
        mouthState: mouthState,
        eyesState: eyesState,
        voiceActivity: smoothedActivity,
        energy: energy,
      ),
    );
  }

  /// 触发情绪动画（Emoji 优先，否则 PAG）
  void _triggerEmotionAnimation(String emotion, String? emoji) {
    if (emoji != null) {
      // 有 emoji：设置 emoji，跳过 PAG
      _currentEmoji = emoji;
      debugPrint('😊 [EMOJI] Set emoji: $emoji');
      debugPrint('🚫 [PAG] Skipped due to emoji priority');
    } else {
      // 无 emoji：清空 emoji，触发 PAG 抽奖
      _currentEmoji = null;
      final selectedAnimation = selectRandomPAG(emotion);
      if (selectedAnimation != null) {
        _pagSrc = selectedAnimation.src;
        final filename = selectedAnimation.src.split('/').last;
        debugPrint('🎨 [PAG] Triggered: $emotion → $filename');
      }
    }
  }

  /// Reset PAG animation (called when PAG animation ends)
  void resetPAG() {
    _pagSrc = null;
  }

  /// Reset Emoji (called when Emoji overlay animation ends)
  void resetEmoji() {
    _currentEmoji = null;
  }

  /// Get current detected state (for external coordination)
  ActorState getCurrentState() {
    return _currentDetectedState;
  }

  /// Cleanup resources
  void destroy() {
    _eyesStateManager.destroy();
    _mouthController.reset();
    _pagSrc = null;
  }
}

/// Create a frame selector instance
FrameSelector createFrameSelector({
  required VadConfig vadConfig,
  required PauseDetectionConfig pauseDetectionConfig,
  EyesLifecycleConfig? eyesLifecycleConfig,
  EyesTimingConfig? eyesTimingConfig,
  MouthConfig? mouthConfig,
}) {
  return FrameSelector(
    vadConfig: vadConfig,
    pauseDetectionConfig: pauseDetectionConfig,
    eyesLifecycleConfig: eyesLifecycleConfig,
    eyesTimingConfig: eyesTimingConfig,
    mouthConfig: mouthConfig,
  );
}
