import '../data/tagging_repository.dart';
import '../domain/tagging_models.dart';

/// Snapshot of a merchant rule available to the inference pipeline.
final class MerchantTagRuleSnapshot {
  final String tagId;
  final int evidenceCount;
  final double confidence;
  final String createdBy;

  const MerchantTagRuleSnapshot({
    required this.tagId,
    required this.evidenceCount,
    required this.confidence,
    required this.createdBy,
  });
}

/// Runtime context passed to every tagger in the pipeline.
final class TaggingContext {
  /// Merchant rules keyed by fingerprint string.
  final Map<String, MerchantTagRuleSnapshot> merchantRules;

  /// Opaque spending-memory priors; each tagger extracts what it needs.
  final Map<String, Object?> spendingMemory;

  /// Active tag catalog for this run.
  final List<TagDefinition> catalog;

  const TaggingContext({
    required this.merchantRules,
    required this.spendingMemory,
    required this.catalog,
  });

  static TaggingContext fromRecords(
    List<MerchantRuleRecord> rules,
    List<TagDefinition> catalog,
  ) {
    return TaggingContext(
      merchantRules: {
        for (final r in rules)
          r.fingerprint: MerchantTagRuleSnapshot(
            tagId: r.tagId,
            evidenceCount: r.evidenceCount,
            confidence: r.confidence,
            createdBy: r.createdBy,
          ),
      },
      spendingMemory: const {},
      catalog: catalog,
    );
  }
}

/// A single stage in the ordered inference pipeline.
abstract interface class CandidateTagger {
  String get id;

  Future<TaggingCandidate?> candidate(
    TaggingTransaction transaction,
    TaggingContext context,
  );
}
