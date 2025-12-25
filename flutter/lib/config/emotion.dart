// ============================================================================
// Type Definitions
// ============================================================================

/// Tag type enumeration
enum TagType {
  emotion,
  emoji,
  progress,
  unknown,
}

/// Represents a parsed tag from the text
class Tag {
  final TagType type;
  final String value; // For emotion: the emotion name; For emoji: the URL; For progress: the numeric value
  final String raw; // Original tag text including brackets
  final int start; // Start position in original text
  final int end; // End position in original text

  const Tag({
    required this.type,
    required this.value,
    required this.raw,
    required this.start,
    required this.end,
  });
}

/// Result of parsing tags from text
class ParseResult {
  final String cleanText; // Text with all tags removed
  final List<Tag> tags; // All parsed tags

  const ParseResult({
    required this.cleanText,
    required this.tags,
  });
}

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
final Map<String, String> synonymToCoreEmotion = _buildSynonymMap();

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
// Helper Functions
// ============================================================================

/// Finds the matching closing bracket for a tag
/// [text] - The text to search in
/// [start] - The starting position of the opening bracket
/// Returns the position of the closing bracket, or -1 if not found
int _findClosingBracket(String text, int start) {
  int depth = 0;
  for (int i = start; i < text.length; i++) {
    if (text[i] == '[') {
      depth++;
    } else if (text[i] == ']') {
      depth--;
      if (depth == 0) {
        return i;
      }
    }
  }
  return -1; // No closing bracket found
}

/// Detects the type of a tag based on its content
/// [content] - The content inside the brackets (without brackets)
/// Returns the tag type and extracted value
({TagType type, String value}) _detectTagType(String content) {
  content = content.trim();

  // 1. Check for emoji format: emoji:url
  if (content.startsWith('emoji:')) {
    // Extract full URL after "emoji:"
    final value = content.substring(6).trim();
    return (type: TagType.emoji, value: value);
  }

  // 2. Check for progress format: progress:number
  if (content.startsWith('progress:')) {
    final parts = content.split(':');
    if (parts.length > 1) {
      final value = parts[1];
      final parsed = double.tryParse(value);
      if (parsed != null) {
        return (type: TagType.progress, value: value);
      }
    }
  }

  // 3. Check if it's a simple emotion tag (single word with only letters)
  if (!content.contains(':') && RegExp(r'^[a-zA-Z]+$').hasMatch(content)) {
    return (type: TagType.emotion, value: content);
  }

  return (type: TagType.unknown, value: content);
}

/// Parses text and extracts all tags
/// [text] - The input text with tags
/// Returns ParseResult containing clean text and extracted tags
ParseResult _parseText(String text) {
  if (text.isEmpty) {
    return const ParseResult(cleanText: '', tags: []);
  }

  final tags = <Tag>[];
  final cleanParts = <String>[];
  int i = 0;
  int lastEnd = 0;

  while (i < text.length) {
    if (text[i] == '[') {
      // Found potential tag start
      final startPos = i;
      final endPos = _findClosingBracket(text, i);

      if (endPos > i) {
        // Valid tag found
        final tagContent = text.substring(i + 1, endPos);
        final raw = text.substring(i, endPos + 1);

        final (:type, :value) = _detectTagType(tagContent);
        final tag = Tag(
          type: type,
          value: value,
          raw: raw,
          start: startPos,
          end: endPos + 1,
        );

        tags.add(tag);

        // Add text before tag to clean parts
        if (lastEnd < startPos) {
          cleanParts.add(text.substring(lastEnd, startPos));
        }

        i = endPos + 1;
        lastEnd = i;
      } else {
        // No matching closing bracket found
        // Add text before the unclosed bracket
        if (lastEnd < startPos) {
          cleanParts.add(text.substring(lastEnd, startPos));
        }
        // Discard everything from the unclosed bracket onwards
        break;
      }
    } else {
      i++;
    }
  }

  // Add remaining text only if we didn't encounter an unclosed bracket
  if (i >= text.length && lastEnd < text.length) {
    cleanParts.add(text.substring(lastEnd));
  }

  return ParseResult(
    cleanText: cleanParts.join('').trim(),
    tags: tags,
  );
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
    final coreEmotion = synonymToCoreEmotion[emotionWord.toLowerCase()];
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

// ============================================================================
// Extended Tag Extraction
// ============================================================================

/// 扩展标签提取结果（包含情绪、进度、emoji）
class ExtractTagsResult {
  final String emotion;
  final String cleanText;
  final double? progress;
  final String? emoji;

  const ExtractTagsResult({
    required this.emotion,
    required this.cleanText,
    this.progress,
    this.emoji,
  });
}

/// 从文本中提取所有标签（情绪、emoji、进度）
/// [text] - 包含标签的文本（如 "[happy] Hello [emoji:https://...gif] [progress:0.5]"）
/// 返回提取的情绪标签、清理后的文本、进度值和emoji URL
ExtractTagsResult extractTags(String text) {
  // 1. Parse text and extract all tags
  final parseResult = _parseText(text);

  // 2. Process emotion (preserve existing logic)
  final emotionTag = parseResult.tags
      .where((tag) => tag.type == TagType.emotion)
      .firstOrNull;
  String emotion = '[peace]'; // Default value

  if (emotionTag != null) {
    final emotionWithBrackets = '[${emotionTag.value}]';

    // 2.1. Check if it's already a core emotion
    if (emotionMap.containsKey(emotionWithBrackets)) {
      emotion = emotionWithBrackets;
    } else {
      // 2.2. Try synonym mapping
      final coreEmotion =
          synonymToCoreEmotion[emotionTag.value.toLowerCase()];
      if (coreEmotion != null) {
        // ignore: avoid_print
        print('🔄 [EMOTION MAPPING] $emotionWithBrackets → $coreEmotion');
        emotion = coreEmotion;
      } else {
        // 2.3. Mapping failed - return original tag (will trigger "reuse previous frame" logic)
        // ignore: avoid_print
        print(
            '⚠️ [EMOTION MAPPING] $emotionWithBrackets is not a core emotion and has no synonym mapping');
        emotion = emotionWithBrackets;
      }
    }
  }

  // 3. Extract first progress value
  final progressTag = parseResult.tags
      .where((tag) => tag.type == TagType.progress)
      .firstOrNull;
  double? progress;
  if (progressTag != null) {
    final parsed = double.tryParse(progressTag.value);
    if (parsed != null && !parsed.isNaN) {
      progress = parsed;
    }
  }

  // 4. Extract first emoji URL
  final emojiTag = parseResult.tags
      .where((tag) => tag.type == TagType.emoji)
      .firstOrNull;
  final emoji = emojiTag?.value;

  return ExtractTagsResult(
    emotion: emotion,
    cleanText: parseResult.cleanText,
    progress: progress,
    emoji: emoji,
  );
}
