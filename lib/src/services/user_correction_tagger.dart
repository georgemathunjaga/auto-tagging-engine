import '../data/tagging_repository.dart';
import '../domain/tagging_models.dart';
import 'candidate_tagger.dart';
import 'merchant_fingerprint.dart';

/// Checks whether the user has explicitly corrected this merchant before.
/// User corrections are stored as merchant rules with `createdBy: 'user'`
/// and always outrank every other local tagger.
final class UserCorrectionTagger implements CandidateTagger {
  final TaggingRepository _repository;
  final MerchantFingerprint _fingerprint;

  const UserCorrectionTagger({
    required TaggingRepository repository,
    required MerchantFingerprint fingerprint,
  })  : _repository = repository,
        _fingerprint = fingerprint;

  @override
  String get id => 'user_correction.v1';

  @override
  Future<TaggingCandidate?> candidate(
    TaggingTransaction transaction,
    TaggingContext context,
  ) async {
    final key = _fingerprint.forTransaction(transaction);
    final rule = context.merchantRules[key];
    if (rule == null || rule.createdBy != 'user') return null;

    return TaggingCandidate(
      tagId: rule.tagId,
      confidence: 1.0,
      source: TagAssignmentSource.userCorrection,
      reasonCode: 'user_correction',
      version: id,
      evidence: {'evidenceCount': rule.evidenceCount},
    );
  }
}
