// Frame Selector - Unified Animation Frame Selection
//
// 统一的帧选择器，封装所有动画状态更新逻辑。
//
// 核心理念：
// 1. 纯函数处理每一帧的数据
// 2. 不依赖外部状态机，而是推导出当前应该处于的状态
// 3. 调用方负责协调状态机事件触发

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

/// 输入数据 - 每一帧的原始数据
class FrameInput {
  /// 音频特征（来自 AudioAnalyzer）
  final VoiceMetrics audioMetrics;

  /// 待处理的字幕（新字幕到达时才有值）
  final PendingSubtitle? pendingSubtitle;

  /// 当前帧编号
  final int frameNumber;

  const FrameInput({
    required this.audioMetrics,
    this.pendingSubtitle,
    required this.frameNumber,
  });
}

/// 待处理的字幕
class PendingSubtitle {
  final String emotion;
  final String id;
  final String content;

  const PendingSubtitle({
    required this.emotion,
    required this.id,
    required this.content,
  });
}

/// 显示的字幕信息
class DisplayedSubtitle {
  final String id;
  final String content;
  final String emotion;

  const DisplayedSubtitle({
    required this.id,
    required this.content,
    required this.emotion,
  });
}

/// PAG 动画输出
class PAGOutput {
  final String src;
  final bool isPlaying;

  const PAGOutput({required this.src, required this.isPlaying});
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

  /// PAG 动画信息（如果需要显示）
  final PAGOutput? pag;

  /// 检测到的会话状态（推导结果）
  final ActorState detectedState;

  /// 情绪标签（用于字幕显示）
  final String currentEmotion;

  /// 是否显示新字幕（pendingSubtitle 被消费）
  final bool shouldDisplaySubtitle;

  /// 显示的字幕信息
  final DisplayedSubtitle? displayedSubtitle;

  /// 调试信息
  final FrameDebugInfo? debug;

  const FrameOutput({
    required this.imageUrl,
    this.pag,
    required this.detectedState,
    required this.currentEmotion,
    required this.shouldDisplaySubtitle,
    this.displayedSubtitle,
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
  final int frameInterval;

  // Internal Controllers
  late final MouthController _mouthController;
  late final EyesStateManager _eyesStateManager;
  late final VoiceActivityManager _voiceActivityManager;
  late final SpeechHistoryManager _speechHistoryManager;

  // Internal State
  String _currentEmotion = '[peace]';
  ActorState _currentDetectedState = ActorState.idle;

  // PAG Animation State
  String? _pagSrc;
  String? _lastSubtitleId;

  FrameSelector({
    required this.vadConfig,
    required this.pauseDetectionConfig,
    required this.frameInterval,
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

  /// Select animation frame based on emotion, mouth state, and eyes state
  String _selectFrame(
    String emotion,
    MouthIntensity mouthState,
    EyesState eyesState,
  ) {
    // Get emotion image set
    final imageSet = getEmotionImageSet(emotion);
    if (imageSet == null) {
      throw Exception(
        "[ANIMATION] Emotion '$emotion' not found - backend data integrity error",
      );
    }

    // Select image based on eyes and mouth state
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
    final pendingSubtitle = input.pendingSubtitle;
    final frameNumber = input.frameNumber;

    final energy = audioMetrics.energy;
    final zcr = audioMetrics.zcr;

    // 1. Classify voice activity
    final newVoiceActivity = classifyVoiceActivity(energy, zcr, vadConfig);
    final smoothedActivity = _voiceActivityManager.smooth(newVoiceActivity);

    // 2. Check if we should display pending subtitle (voice detected)
    bool shouldDisplaySubtitle = false;
    DisplayedSubtitle? displayedSubtitle;

    if (pendingSubtitle != null &&
        newVoiceActivity != VoiceActivityState.quiet) {
      // New subtitle arrives + voice detected → display it
      shouldDisplaySubtitle = true;
      displayedSubtitle = DisplayedSubtitle(
        id: pendingSubtitle.id,
        content: pendingSubtitle.content,
        emotion: pendingSubtitle.emotion,
      );

      // Update emotion
      _currentEmotion = pendingSubtitle.emotion;

      // Record subtitle frame in history
      _speechHistoryManager.recordSubtitleFrame(frameNumber);

      // Trigger PAG animation (if random selection succeeds)
      _triggerPAGAnimation(pendingSubtitle.emotion, pendingSubtitle.id);

      // State detection: subtitle + voice → SPEAKING
      _currentDetectedState = ActorState.speaking;

      // Reset speech history when entering speaking state
      _speechHistoryManager.reset();
    }

    // 3. Update speech history for finish detection
    final speechHistoryResult = _speechHistoryManager.update(
      SpeechHistoryInput(
        voiceActivity: smoothedActivity,
        energy: energy,
        frame: frameNumber,
      ),
    );

    // 4. Detect state transitions
    if (speechHistoryResult.shouldFinishSpeaking) {
      // Sustained quiet → IDLE
      _currentDetectedState = ActorState.idle;
      _speechHistoryManager.setIdleStateStartFrame(frameNumber);
      _lastSubtitleId = null; // Reset for next turn
    } else if (speechHistoryResult.shouldResumeFromIdle &&
        _currentDetectedState == ActorState.idle) {
      // Strong signal after idle → SPEAKING
      _currentDetectedState = ActorState.speaking;
      _speechHistoryManager.reset();
    }

    // 5. Update eyes state (natural blinking)
    final eyesState = _eyesStateManager.update();

    // 6. Update mouth state (audio-driven, state-aware)
    final audioFeatures = AudioFeatureSet(
      energy: energy,
      zcr: zcr,
      spectralCentroid: audioMetrics.spectralCentroid,
      highFreqEnergy: audioMetrics.highFreqEnergy,
    );
    final mouthState = _mouthController.update(audioFeatures);

    // 7. Select character frame (emotion + mouth + eyes)
    final imageUrl = _selectFrame(_currentEmotion, mouthState, eyesState);

    // 8. Return output
    return FrameOutput(
      imageUrl: imageUrl,
      pag: _pagSrc != null ? PAGOutput(src: _pagSrc!, isPlaying: true) : null,
      detectedState: _currentDetectedState,
      currentEmotion: _currentEmotion,
      shouldDisplaySubtitle: shouldDisplaySubtitle,
      displayedSubtitle: displayedSubtitle,
      debug: FrameDebugInfo(
        mouthState: mouthState,
        eyesState: eyesState,
        voiceActivity: smoothedActivity,
        energy: energy,
      ),
    );
  }

  /// Trigger PAG animation for emotion (with random selection)
  void _triggerPAGAnimation(String emotion, String subtitleId) {
    // Check if this is a new subtitle
    if (subtitleId == _lastSubtitleId) {
      return; // Already processed
    }

    // Random selection (reads from global config)
    final selectedAnimation = selectRandomPAG(emotion);

    if (selectedAnimation != null) {
      final filename = selectedAnimation.src.split('/').last;
      debugPrint('[Frame Selector] PAG triggered: $emotion → $filename');
      _pagSrc = selectedAnimation.src;
    }

    _lastSubtitleId = subtitleId;
  }

  /// Reset PAG animation (called when PAG animation ends)
  void resetPAG() {
    _pagSrc = null;
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
  required int frameInterval,
  EyesLifecycleConfig? eyesLifecycleConfig,
  EyesTimingConfig? eyesTimingConfig,
  MouthConfig? mouthConfig,
}) {
  return FrameSelector(
    vadConfig: vadConfig,
    pauseDetectionConfig: pauseDetectionConfig,
    frameInterval: frameInterval,
    eyesLifecycleConfig: eyesLifecycleConfig,
    eyesTimingConfig: eyesTimingConfig,
    mouthConfig: mouthConfig,
  );
}
