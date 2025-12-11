// ============================================================================
// Core Emotion Mapping
// ============================================================================

const Map<String, String> emotionMap = {
  '[happy]': '开心',
  '[peace]': '平静',
  '[excited]': '兴奋',
  '[angry]': '愤怒',
  '[surprised]': '惊讶',
  '[worried]': '担心',
  '[serious]': '严肃',
  '[speechless]': '无语',
};

// ============================================================================
// Emotion Synonym Mapping
// ============================================================================

/// Emotion synonym mapping: Core emotions to their English synonyms
/// Used to map LLM-generated emotion tags to supported core emotions
const Map<String, List<String>> emotionSynonymMap = {
  '[happy]': [
    'joyful',
    'delighted',
    'cheerful',
    'pleased',
    'blissful',
    'joyous',
    'content',
    'gratified',
    'elated',
    'thrilled',
  ],
  '[excited]': [
    'enthusiastic',
    'feverish',
    'agitated',
    'eager',
    'exhilarated',
    'animated',
    'vibrant',
    'fired-up',
    'electrified',
  ],
  '[angry]': [
    'furious',
    'irritated',
    'annoyed',
    'indignant',
    'resentful',
    'wrathful',
    'exasperated',
    'cross',
    'outraged',
    'provoked',
  ],
  '[peace]': [
    'peaceful',
    'serene',
    'tranquil',
    'composed',
    'unruffled',
    'relaxed',
    'placid',
    'cool',
    'collected',
    'undisturbed',
    'calm',
  ],
  '[worried]': [
    'anxious',
    'apprehensive',
    'concerned',
    'nervous',
    'distressed',
    'uneasy',
    'perturbed',
    'on edge',
    'restless',
    'troubled',
  ],
  '[speechless]': [
    'dumbfounded',
    'lost for words',
    'mute',
    'unable to speak',
  ],
  '[surprised]': [
    'astonished',
    'amazed',
    'startled',
    'flabbergasted',
    'taken aback',
  ],
  '[serious]': [
    'solemn',
    'sober',
    'earnest',
    'grave',
    'sincere',
    'thoughtful',
    'intent',
    'determined',
    'committed',
    'unsmiling',
  ],
};

/// Reverse lookup map: Synonym (lowercase) -> Core emotion tag
/// Built from emotionSynonymMap for efficient lookup
final Map<String, String> _synonymToCoreEmotion = _buildSynonymMap();

Map<String, String> _buildSynonymMap() {
  final map = <String, String>{};
  for (final entry in emotionSynonymMap.entries) {
    final coreEmotion = entry.key;
    for (final synonym in entry.value) {
      map[synonym.toLowerCase()] = coreEmotion;
    }
  }
  return map;
}

// ============================================================================
// Emotion Extraction
// ============================================================================

/// 情绪提取结果
class EmotionExtractResult {
  final String emotion;
  final String cleanText;

  const EmotionExtractResult({
    required this.emotion,
    required this.cleanText,
  });
}

/// 从文本中提取情绪标签
/// [text] - 包含情绪标签的文本（如 "[happy] Hello!"）
/// 返回提取的情绪标签和清理后的文本
EmotionExtractResult extractEmotion(String text) {
  final emotionRegex = RegExp(r'^\[([^\]]+)\]\s*');
  final match = emotionRegex.firstMatch(text);

  if (match != null) {
    final emotionWord = match.group(1)!; // e.g., "joyful"
    final emotionTag = '[$emotionWord]'; // e.g., "[joyful]"
    final cleanText = text.replaceFirst(emotionRegex, '');

    // 1. Check if it's already a core emotion
    if (emotionMap.containsKey(emotionTag)) {
      return EmotionExtractResult(emotion: emotionTag, cleanText: cleanText);
    }

    // 2. Try synonym mapping
    final coreEmotion = _synonymToCoreEmotion[emotionWord.toLowerCase()];
    if (coreEmotion != null) {
      // ignore: avoid_print
      print('🔄 [EMOTION MAPPING] $emotionTag → $coreEmotion');
      return EmotionExtractResult(emotion: coreEmotion, cleanText: cleanText);
    }

    // 3. Mapping failed - return original tag (will trigger "reuse previous frame" logic)
    // ignore: avoid_print
    print('⚠️ [EMOTION MAPPING] $emotionTag is not a core emotion and has no synonym mapping');
    return EmotionExtractResult(emotion: emotionTag, cleanText: cleanText);
  }

  // No emotion tag found in text
  return EmotionExtractResult(emotion: '[peace]', cleanText: text);
}
