// Small Emotion Configuration
//
// 小表情动画的配置常量

/// Individual animation weight
/// 每个动画变体的权重
const int animationWeight = 3;

/// Default empty weight
/// 默认空状态权重（不显示动画的概率权重）
///
/// Production values:
/// - EMPTY_WEIGHT = 7: 30-56% show
/// - 1 variant (worried, excited, surprised): 3/(7+3) = 30% show
/// - 2 variants (serious, speechless): 6/(7+6) = 46% show
/// - 3 variants (angry, happy): 9/(7+9) = 56% show
const int defaultEmptyWeight = 0;
