import '../domain/tagging_models.dart';
import '../tagging_config.dart';

final class TaggingConfidencePolicy {
  final TaggingConfidenceConfig _config;

  const TaggingConfidencePolicy({
    TaggingConfidenceConfig config = const TaggingConfidenceConfig(),
  }) : _config = config;

  TaggingAction decide(
    TaggingTransaction transaction,
    TagDefinition tag,
    TaggingCandidate candidate,
  ) {
    if (!_directionCompatible(transaction.direction, tag.direction)) {
      return TaggingAction.suppress;
    }
    if (candidate.confidence < _config.suggestThreshold) {
      return TaggingAction.suppress;
    }
    final threshold = _config.sensitiveTagIds.contains(tag.id)
        ? _config.sensitiveAutoApplyThreshold
        : _config.autoApplyThreshold;
    return candidate.confidence >= threshold
        ? TaggingAction.autoApply
        : TaggingAction.suggest;
  }

  bool _directionCompatible(String transactionDirection, TagDirection tagDirection) {
    if (tagDirection == TagDirection.neutral) return true;
    if (transactionDirection == 'incoming') {
      return tagDirection == TagDirection.income;
    }
    if (transactionDirection == 'outgoing') {
      return tagDirection == TagDirection.expense;
    }
    return true;
  }
}
