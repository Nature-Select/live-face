# LiveFace 模块使用说明

LiveFace 是一个基于音频驱动的虚拟角色表情动画系统，用于实时驱动角色图片切换和 PAG 动画播放。

## 目录

- [概述](#概述)
- [核心架构](#核心架构)
- [快速开始](#快速开始)
- [接入声网 (Agora)](#接入声网-agora)
- [详细 API](#详细-api)
- [配置说明](#配置说明)

---

## 概述

### 功能

1. **音频驱动的嘴型动画**：根据音频能量实时切换张嘴/闭嘴图片
2. **自然眨眼动画**：支持慢速、快速、双眨眼三种模式
3. **情绪图片切换**：根据字幕中的情绪标签切换对应表情
4. **PAG 动画播放**：在情绪切换时随机触发小表情动画

### 核心原理

```
声网音频数据 → AudioAnalyzer → VoiceMetrics → FrameSelector → FrameOutput
                                                    ↓
                                              图片 URL + PAG 动画
```

---

## 核心架构

### 目录结构

```
lib/liveface/
├── config/                    # 配置文件
│   ├── audio_config.dart      # 音频分析 + VAD 配置
│   ├── eyes_config.dart       # 眨眼动画配置
│   ├── mouth_config.dart      # 嘴型动画配置
│   └── small_emotion_config.dart  # PAG 动画配置
│
└── modules/                   # 核心模块
    ├── types.dart             # 共享类型定义
    ├── frame_selector.dart    # 帧选择器（核心入口）
    ├── audio_analysis.dart    # 音频分析
    ├── vad.dart               # 语音活动检测
    ├── mouth_controller.dart  # 嘴型控制器
    ├── eyes_controller.dart   # 眨眼控制器
    ├── speech_history.dart    # 语音历史管理
    ├── emotion_image_sets.dart    # 情绪图片管理
    └── small_emotion_controller.dart  # PAG 动画管理
```

### 核心类

| 类名 | 说明 |
|-----|------|
| `FrameSelector` | 统一帧选择器，协调所有子系统 |
| `AudioAnalyzer` | 音频特征提取 |
| `VoiceActivityManager` | 语音活动状态管理 |
| `MouthController` | 嘴型动画控制 |
| `EyesStateManager` | 眨眼动画控制 |
| `EmotionImageSetsManager` | 情绪图片集管理（单例） |
| `SmallEmotionManager` | PAG 动画管理（单例） |

---

## 快速开始

### 1. 初始化资源

在应用启动时，设置情绪图片和 PAG 动画资源：

```dart
import 'package:elys_realtime/liveface/modules/emotion_image_sets.dart';
import 'package:elys_realtime/liveface/modules/small_emotion_controller.dart';

void initLiveFaceResources() {
  // 1. 设置情绪图片集
  setEmotionImageSets({
    '[calm]': EmotionImageSet(
      eyesOpenMouthClosed: 'https://cdn.example.com/calm_eo_mc.png',
      eyesOpenMouthOpen: 'https://cdn.example.com/calm_eo_mo.png',
      eyesClosedMouthClosed: 'https://cdn.example.com/calm_ec_mc.png',
      eyesClosedMouthOpen: 'https://cdn.example.com/calm_ec_mo.png',
    ),
    '[happy]': EmotionImageSet(
      eyesOpenMouthClosed: 'https://cdn.example.com/happy_eo_mc.png',
      eyesOpenMouthOpen: 'https://cdn.example.com/happy_eo_mo.png',
      eyesClosedMouthClosed: 'https://cdn.example.com/happy_ec_mc.png',
      eyesClosedMouthOpen: 'https://cdn.example.com/happy_ec_mo.png',
    ),
    // ... 其他情绪
  });

  // 2. 设置 PAG 动画资源
  setPAGMap({
    '[happy]': [
      'https://cdn.example.com/happy_1.pag',
      'https://cdn.example.com/happy_2.pag',
    ],
    '[angry]': [
      'https://cdn.example.com/angry_1.pag',
    ],
    // ... 其他情绪
  });
}
```

### 2. 创建 FrameSelector

```dart
import 'package:elys_realtime/liveface/config/audio_config.dart';
import 'package:elys_realtime/liveface/modules/frame_selector.dart';

final frameSelector = FrameSelector(
  vadConfig: defaultVadConfig,
  pauseDetectionConfig: defaultPauseDetectionConfig,
  frameInterval: 42, // 约 24fps (1000ms / 24 ≈ 42ms)
);
```

### 3. 处理音频帧

```dart
import 'package:elys_realtime/liveface/modules/audio_analysis.dart';

// 创建音频分析器
final audioAnalyzer = AudioAnalyzer();

// 每帧处理
void onAudioFrame(int volume, int frameNumber, PendingSubtitle? subtitle) {
  // 1. 从声网音量数据生成音频特征
  final audioMetrics = audioAnalyzer.updateFromVolume(volume);

  // 2. 构建帧输入
  final input = FrameInput(
    audioMetrics: audioMetrics,
    pendingSubtitle: subtitle,
    frameNumber: frameNumber,
  );

  // 3. 处理帧，获取输出
  final output = frameSelector.processFrame(input);

  // 4. 使用输出更新 UI
  updateCharacterImage(output.imageUrl);

  if (output.pag != null && output.pag!.isPlaying) {
    playPAGAnimation(output.pag!.src);
  }

  if (output.shouldDisplaySubtitle && output.displayedSubtitle != null) {
    showSubtitle(output.displayedSubtitle!.content);
  }
}
```

---

## 接入声网 (Agora)

### 方式一：使用音量回调（推荐）

使用 `onAudioVolumeIndication` 回调，简单易用：

```dart
import 'package:agora_rtc_engine/agora_rtc_engine.dart';

class LiveFaceAgoraHandler {
  late final RtcEngine _engine;
  late final FrameSelector _frameSelector;
  late final AudioAnalyzer _audioAnalyzer;
  int _frameNumber = 0;
  PendingSubtitle? _pendingSubtitle;

  Future<void> init() async {
    _engine = createAgoraRtcEngine();
    await _engine.initialize(const RtcEngineContext(appId: 'YOUR_APP_ID'));

    // 启用音量回调，间隔 42ms（约 24fps）
    await _engine.enableAudioVolumeIndication(
      interval: 42,
      smooth: 3,
      reportVad: true,
    );

    // 初始化 LiveFace
    _frameSelector = FrameSelector(
      vadConfig: defaultVadConfig,
      pauseDetectionConfig: defaultPauseDetectionConfig,
      frameInterval: 42,
    );
    _audioAnalyzer = AudioAnalyzer();

    // 注册音量回调
    _engine.registerEventHandler(RtcEngineEventHandler(
      onAudioVolumeIndication: _onAudioVolumeIndication,
    ));
  }

  void _onAudioVolumeIndication(
    RtcConnection connection,
    List<AudioVolumeInfo> speakers,
    int speakerNumber,
    int totalVolume,
  ) {
    // 查找 AI 说话者的音量（uid=0 表示远端混音）
    int aiVolume = 0;
    for (final speaker in speakers) {
      if (speaker.uid == 0) { // 或者使用 AI 的具体 uid
        aiVolume = speaker.volume ?? 0;
        break;
      }
    }

    // 处理帧
    _frameNumber++;
    final audioMetrics = _audioAnalyzer.updateFromVolume(aiVolume);

    final output = _frameSelector.processFrame(FrameInput(
      audioMetrics: audioMetrics,
      pendingSubtitle: _pendingSubtitle,
      frameNumber: _frameNumber,
    ));

    // 消费 pendingSubtitle
    if (output.shouldDisplaySubtitle) {
      _pendingSubtitle = null;
    }

    // 通知 UI 更新
    _onFrameOutput(output);
  }

  // 当收到新字幕时调用
  void onSubtitleReceived(String id, String content, String emotion) {
    _pendingSubtitle = PendingSubtitle(
      id: id,
      content: content,
      emotion: emotion, // 如 '[happy]', '[calm]'
    );
  }

  void _onFrameOutput(FrameOutput output) {
    // 更新角色图片
    // 播放 PAG 动画
    // 显示字幕
  }

  void dispose() {
    _frameSelector.destroy();
    _engine.release();
  }
}
```

### 方式二：使用原始音频数据

如果需要更精确的音频分析，可以使用 `AudioFrameObserver`：

```dart
class RawAudioHandler extends AudioFrameObserver {
  final AudioAnalyzer _audioAnalyzer = AudioAnalyzer();

  @override
  bool onPlaybackAudioFrame(AudioFrame audioFrame) {
    // 将 PCM16 数据转换为归一化样本
    final samples = convertPcm16ToSamples(audioFrame.buffer);

    // 从原始样本提取音频特征
    final metrics = _audioAnalyzer.updateFromSamples(samples);

    // 处理帧...
    return true;
  }
}

// 注册
await _engine.getMediaEngine().registerAudioFrameObserver(RawAudioHandler());
```

---

## 详细 API

### FrameSelector

核心帧选择器，协调所有动画子系统。

#### 构造函数

```dart
FrameSelector({
  required VadConfig vadConfig,
  required PauseDetectionConfig pauseDetectionConfig,
  required int frameInterval,
  EyesLifecycleConfig? eyesLifecycleConfig,
  EyesTimingConfig? eyesTimingConfig,
  MouthConfig? mouthConfig,
})
```

#### 方法

| 方法 | 说明 |
|-----|------|
| `FrameOutput processFrame(FrameInput input)` | 处理单帧，返回渲染输出 |
| `void resetPAG()` | 重置 PAG 动画状态（动画播放完毕后调用） |
| `ActorState getCurrentState()` | 获取当前检测到的状态 |
| `void destroy()` | 清理资源 |

### FrameInput

帧输入数据：

```dart
class FrameInput {
  final VoiceMetrics audioMetrics;    // 音频特征
  final PendingSubtitle? pendingSubtitle;  // 待显示的字幕
  final int frameNumber;              // 当前帧编号
}
```

### FrameOutput

帧输出数据：

```dart
class FrameOutput {
  final String imageUrl;              // 角色图片 URL
  final PAGOutput? pag;               // PAG 动画信息
  final ActorState detectedState;     // 检测到的状态（idle/speaking）
  final String currentEmotion;        // 当前情绪标签
  final bool shouldDisplaySubtitle;   // 是否应显示字幕
  final DisplayedSubtitle? displayedSubtitle;  // 字幕内容
  final FrameDebugInfo? debug;        // 调试信息
}
```

### PAGOutput

PAG 动画信息：

```dart
class PAGOutput {
  final String src;      // PAG 文件 URL
  final bool isPlaying;  // 是否正在播放
}
```

---

## 配置说明

### VadConfig - 语音活动检测配置

```dart
const defaultVadConfig = VadConfig(
  lowEnergyThreshold: 0.002,    // 低能量阈值（静音检测）
  highEnergyThreshold: 0.012,   // 高能量阈值（说话检测）
  pauseEnergyThreshold: 0.004,  // 暂停能量阈值
  zcrWeight: 0.3,               // 过零率权重
  smoothingFactor: 0.6,         // 平滑因子
  debounceFrames: 3,            // 防抖帧数
);
```

### PauseDetectionConfig - 暂停检测配置

```dart
const defaultPauseDetectionConfig = PauseDetectionConfig(
  pauseThresholdFrames: 7,      // 暂停检测阈值 (约 0.3s @ 24fps)
  finishedThresholdFrames: 36,  // 结束检测阈值 (约 1.5s @ 24fps)
  zeroEnergyFrames: 24,         // 零能量帧数 (约 1.0s @ 24fps)
  minFramesAfterSubtitle: 72,   // 字幕后最小帧数 (约 3.0s @ 24fps)
  minIdleDuration: 12,          // 最小空闲时长 (约 0.5s @ 24fps)
  strongSignalMultiplier: 0.5,  // 强信号倍数
);
```

### EyesLifecycleConfig - 眨眼配置

```dart
const defaultEyesLifecycleConfig = EyesLifecycleConfig(
  idle: EyesLifecycleStateConfig(
    blinkEnabled: true,
    modeProbability: BlinkModeProbability(
      slow: 0.9,     // 90% 慢速眨眼
      fast: 0,       // 0% 快速眨眼
      double_: 0.1,  // 10% 双眨眼
    ),
  ),
  speaking: EyesLifecycleStateConfig(
    blinkEnabled: true,
    modeProbability: BlinkModeProbability(
      slow: 0,       // 0% 慢速眨眼
      fast: 1,       // 100% 快速眨眼
      double_: 0,    // 0% 双眨眼
    ),
  ),
);
```

### EyesTimingConfig - 眨眼时间配置

```dart
const defaultEyesTimingConfig = EyesTimingConfig(
  slowBlinkDuration: TimingParams(base: 400, variance: 100),  // 慢速眨眼 300-500ms
  fastBlinkDuration: TimingParams(base: 250, variance: 50),   // 快速眨眼 200-300ms
  doubleBlinkPhaseDuration: TimingParams(base: 100, variance: 20),  // 双眨眼相位 80-120ms
  blinkInterval: TimingParams(base: 3500, variance: 800),     // 眨眼间隔 2700-4300ms
);
```

### MouthConfig - 嘴型配置

```dart
const defaultMouthConfig = MouthConfig(
  mouthCloseThreshold: 0.001,      // 闭嘴能量阈值
  maxMouthOpenDuration: 12,        // 最大张嘴帧数
  microPauseThreshold: 0.0008,     // 微停顿阈值
  adaptiveThresholdFactor: 0.8,    // 自适应阈值因子
  mouthDecayRate: 0.85,            // 嘴型衰减率
  decayClosedThreshold: 0.5,       // 衰减闭嘴阈值
  energyHistoryWindow: 8,          // 能量历史窗口
  recentAvgWindow: 4,              // 近期平均窗口
  olderAvgWindow: 4,               // 早期平均窗口
  minEnergyValuesForAdaptive: 6,   // 自适应最小值数量
  energyDropMultiplier: 0.6,       // 能量下降倍数
  featureWeights: MouthFeatureWeights(
    energy: 0.4,           // 能量权重
    zcr: 0.2,              // 过零率权重
    spectralCentroid: 0.0001,  // 频谱质心权重
    highFreqEnergy: 0.4,   // 高频能量权重
  ),
);
```

### SmallEmotionConfig - PAG 动画配置

```dart
const int animationWeight = 3;      // 每个动画的权重
const int defaultEmptyWeight = 7;   // 空状态权重（不显示动画）

// 显示概率计算示例：
// - 1 个变体：3/(7+3) = 30% 显示
// - 2 个变体：6/(7+6) = 46% 显示
// - 3 个变体：9/(7+9) = 56% 显示
```

---

## 完整示例

```dart
import 'package:flutter/material.dart';
import 'package:pag_view/pag_view.dart';

class LiveFaceWidget extends StatefulWidget {
  @override
  State<LiveFaceWidget> createState() => _LiveFaceWidgetState();
}

class _LiveFaceWidgetState extends State<LiveFaceWidget> {
  late final FrameSelector _frameSelector;
  late final AudioAnalyzer _audioAnalyzer;

  String _currentImageUrl = '';
  String? _currentPAGUrl;
  bool _isPAGPlaying = false;

  @override
  void initState() {
    super.initState();
    _initLiveFace();
  }

  void _initLiveFace() {
    // 初始化资源（通常在更早的时机完成）
    _initResources();

    // 创建帧选择器
    _frameSelector = FrameSelector(
      vadConfig: defaultVadConfig,
      pauseDetectionConfig: defaultPauseDetectionConfig,
      frameInterval: 42,
    );
    _audioAnalyzer = AudioAnalyzer();
  }

  void _initResources() {
    setEmotionImageSets({
      '[calm]': EmotionImageSet(
        eyesOpenMouthClosed: 'assets/calm_eo_mc.png',
        eyesOpenMouthOpen: 'assets/calm_eo_mo.png',
        eyesClosedMouthClosed: 'assets/calm_ec_mc.png',
        eyesClosedMouthOpen: 'assets/calm_ec_mo.png',
      ),
      // ... 其他情绪
    });

    setPAGMap({
      '[happy]': ['assets/happy.pag'],
      // ... 其他情绪
    });
  }

  void onAudioFrame(int volume, int frameNumber, PendingSubtitle? subtitle) {
    final audioMetrics = _audioAnalyzer.updateFromVolume(volume);

    final output = _frameSelector.processFrame(FrameInput(
      audioMetrics: audioMetrics,
      pendingSubtitle: subtitle,
      frameNumber: frameNumber,
    ));

    setState(() {
      _currentImageUrl = output.imageUrl;

      if (output.pag != null) {
        _currentPAGUrl = output.pag!.src;
        _isPAGPlaying = true;
      }
    });
  }

  void _onPAGAnimationEnd() {
    setState(() {
      _isPAGPlaying = false;
      _currentPAGUrl = null;
    });
    _frameSelector.resetPAG();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 角色图片
        if (_currentImageUrl.isNotEmpty)
          Image.network(_currentImageUrl),

        // PAG 动画叠加层
        if (_isPAGPlaying && _currentPAGUrl != null)
          PAGView.network(
            _currentPAGUrl!,
            repeatCount: 1,
            onAnimationEnd: _onPAGAnimationEnd,
          ),
      ],
    );
  }

  @override
  void dispose() {
    _frameSelector.destroy();
    super.dispose();
  }
}
```

---

## 状态流转

```
                    ┌─────────────────────────────────────────┐
                    │                                         │
                    ▼                                         │
              ┌─────────┐    字幕+声音    ┌──────────┐        │
              │  IDLE   │ ─────────────► │ SPEAKING │        │
              └─────────┘                └──────────┘        │
                    ▲                          │             │
                    │                          │             │
                    │    持续静音 1.5s         │             │
                    │    或零能量 1.0s         │             │
                    └──────────────────────────┘             │
                                                             │
                    ┌────────────────────────────────────────┘
                    │ 强信号恢复（空闲 0.5s 后检测到强音频）
```

## 图片选择逻辑

```
情绪标签 (emotion) + 嘴巴状态 (mouth) + 眼睛状态 (eyes)
         ↓
┌─────────────────────────────────────────────────────┐
│  EmotionImageSet                                    │
│  ├── eyesOpenMouthClosed   (睁眼闭嘴 - 默认状态)   │
│  ├── eyesOpenMouthOpen     (睁眼张嘴 - 说话中)     │
│  ├── eyesClosedMouthClosed (闭眼闭嘴 - 眨眼时)     │
│  └── eyesClosedMouthOpen   (闭眼张嘴 - 说话+眨眼)  │
└─────────────────────────────────────────────────────┘
```
