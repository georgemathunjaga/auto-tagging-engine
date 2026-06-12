import '../domain/tagging_models.dart';
import '../tagging_config.dart';
import 'candidate_tagger.dart';
import 'merchant_fingerprint.dart';

final class MerchantHistoryTagger implements CandidateTagger {
  final MerchantFingerprint _fingerprint;
  final MerchantHistoryConfig _config;

  const MerchantHistoryTagger({
    required MerchantFingerprint fingerprint,
    MerchantHistoryConfig config = const MerchantHistoryConfig(),
  })  : _fingerprint = fingerprint,
        _config = config;

  @override
  String get id => 'merchant_history.v1';

  @override
  Future<TaggingCandidate?> candidate(
    TaggingTransaction transaction,
    TaggingContext context,
  ) async {
    final key = _fingerprint.forTransaction(transaction);
    final evidence = context.merchantRules[key];
    if (evidence == null) return null;

    final confidence = switch (evidence.evidenceCount) {
      <= 1 => _config.singleEvidenceConfidence,
      2 => _config.doubleEvidenceConfidence,
      _ => _config.strongEvidenceConfidence,
    };

    return TaggingCandidate(
      tagId: evidence.tagId,
      confidence: confidence,
      source: TagAssignmentSource.merchantHistory,
      reasonCode: 'merchant_history',
      version: id,
      evidence: {'count': evidence.evidenceCount},
    );
  }
}
