import '../domain/tagging_models.dart';
import '../tagging_api.dart';

/// A write descriptor for creating or updating a merchant-fingerprint rule.
final class MerchantRuleWrite {
  final String fingerprint;
  final String direction;
  final String tagId;
  final String scope;
  final String createdBy;

  const MerchantRuleWrite({
    required this.fingerprint,
    required this.direction,
    required this.tagId,
    required this.scope,
    this.createdBy = 'auto',
  });
}

/// A merchant rule snapshot keyed by fingerprint (used inside TaggingContext).
final class MerchantRuleRecord {
  final String fingerprint;
  final String tagId;
  final int evidenceCount;
  final double confidence;
  final String createdBy;

  const MerchantRuleRecord({
    required this.fingerprint,
    required this.tagId,
    required this.evidenceCount,
    required this.confidence,
    required this.createdBy,
  });
}

abstract interface class TaggingRepository {
  // ── Assignments ──────────────────────────────────────────────────────────
  Stream<TagAssignment?> watchAssignment(String transactionId);
  Future<TagAssignment?> getAssignment(String transactionId);
  Future<List<TagAssignment>> getAssignments(Iterable<String> transactionIds);

  // ── Catalog ───────────────────────────────────────────────────────────────
  Stream<void> watchCatalogChanges();
  Future<List<TagDefinition>> catalog(TagCatalogQuery query);
  Future<TagDefinition?> getTag(String id);
  Future<void> saveTag(TagDefinition tag);

  // ── Merchant rules ────────────────────────────────────────────────────────
  Future<List<MerchantRuleRecord>> merchantRules();
  Future<MerchantRuleRecord?> getMerchantRule(String fingerprint);

  // ── Operations (atomic write + undo) ─────────────────────────────────────
  Future<void> applyOperation(
    TaggingOperation operation,
    List<TagAssignment> assignments,
    List<MerchantRuleWrite> ruleWrites,
  );
  Future<TaggingOperation?> getOperation(String id);
  Future<void> restoreOperation(TaggingOperation operation);

  // ── Lifecycle ─────────────────────────────────────────────────────────────
  Future<void> dispose();
}
