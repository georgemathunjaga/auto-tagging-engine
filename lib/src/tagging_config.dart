import 'domain/tagging_models.dart';

// ─── Catalog seeding ──────────────────────────────────────────────────────────

/// Controls how the built-in tag catalog is seeded on first install.
enum TagCatalogSeedStrategy {
  /// Use only the built-in MoneyChat tags. Default.
  systemOnly,

  /// Skip built-in tags entirely. The host app must supply all tags via
  /// [TaggingConfig.initialTags].
  replace,

  /// Add [TaggingConfig.initialTags] on top of the built-in catalog.
  /// Duplicate IDs are ignored.
  extend,
}

// ─── Merchant rules ───────────────────────────────────────────────────────────

/// Controls where host-supplied deterministic merchant rules are placed
/// relative to the built-in keyword rules.
enum MerchantRuleStrategy {
  /// Host rules are evaluated before the built-in rules.
  /// Built-in rules still run if no host rule matches. Default.
  extendBefore,

  /// Host rules are evaluated after the built-in rules.
  extendAfter,

  /// Only host-supplied rules are used. Built-in rules are ignored.
  replaceDefaults,
}

/// A single keyword-to-tag mapping supplied by the host app.
final class KeywordTagRule {
  /// Lower-case keywords; a match fires when any appear in the combined
  /// merchant + transaction-type string.
  final Set<String> keywords;

  /// Stable tag ID to return when a keyword matches.
  final String tagId;

  /// Confidence attached to suggestions from this rule (0.0–1.0).
  final double confidence;

  const KeywordTagRule({
    required this.keywords,
    required this.tagId,
    this.confidence = 0.80,
  });
}

// ─── Inference policy ─────────────────────────────────────────────────────────

/// Governs suggestion, auto-apply, and sensitive-category thresholds for the
/// unified inference pipeline.
final class TaggingConfidenceConfig {
  /// Candidates below this value are suppressed and never shown. (0.0–1.0)
  final double suggestThreshold;

  /// Candidates at or above this value are auto-applied for normal tags.
  /// Candidates between [suggestThreshold] and [autoApplyThreshold] are shown
  /// as suggestions only. (0.0–1.0)
  final double autoApplyThreshold;

  /// Candidates must reach this value for tags in [sensitiveTagIds] before
  /// auto-apply is permitted. (0.0–1.0)
  final double sensitiveAutoApplyThreshold;

  /// Stable tag IDs that require [sensitiveAutoApplyThreshold] instead of
  /// [autoApplyThreshold] before auto-apply.
  final Set<String> sensitiveTagIds;

  const TaggingConfidenceConfig({
    this.suggestThreshold = 0.60,
    this.autoApplyThreshold = 0.85,
    this.sensitiveAutoApplyThreshold = 0.92,
    this.sensitiveTagIds = const {'debt', 'loan', 'health'},
  });
}

// ─── Merchant history ─────────────────────────────────────────────────────────

/// Controls merchant-history confidence based on how many times a merchant
/// has been tagged with the same tag.
final class MerchantHistoryConfig {
  /// Confidence assigned after exactly one observed tagging.
  final double singleEvidenceConfidence;

  /// Confidence assigned after exactly two observed taggings.
  final double doubleEvidenceConfidence;

  /// Confidence assigned after three or more observed taggings.
  final double strongEvidenceConfidence;

  /// Evidence older than this still contributes but at dominant-category
  /// weight rather than exact recent-match weight.
  final Duration recentEvidenceWindow;

  const MerchantHistoryConfig({
    this.singleEvidenceConfidence = 0.78,
    this.doubleEvidenceConfidence = 0.90,
    this.strongEvidenceConfidence = 0.94,
    this.recentEvidenceWindow = const Duration(hours: 72),
  });
}

// ─── Auto-tagging runs ────────────────────────────────────────────────────────

/// Governs automatic bulk-tagging runs.
final class AutoTagRunConfig {
  /// Maximum number of transactions that may be auto-applied in a single run.
  final int maximumAutoApply;

  /// Whether the spending-memory prior is permitted to vote in the pipeline.
  /// Set false if the app does not expose a spending-profile feature.
  final bool allowSpendingMemory;

  /// Maximum confidence the spending-memory stage may contribute. Kept below
  /// [TaggingConfidenceConfig.autoApplyThreshold] so it never auto-applies
  /// by itself.
  final double spendingMemoryConfidenceCap;

  const AutoTagRunConfig({
    this.maximumAutoApply = 30,
    this.allowSpendingMemory = true,
    this.spendingMemoryConfidenceCap = 0.82,
  });
}

// ─── Audit and undo ───────────────────────────────────────────────────────────

/// Governs tagging operation audit and undo retention.
final class TaggingAuditConfig {
  /// How long a tagging operation remains undoable after it was applied.
  final Duration undoWindow;

  /// Maximum number of audit records kept. Oldest entries are pruned once
  /// this limit is reached.
  final int maxAuditRecords;

  const TaggingAuditConfig({
    this.undoWindow = const Duration(days: 30),
    this.maxAuditRecords = 250,
  });
}

// ─── Remote AI ────────────────────────────────────────────────────────────────

/// Identifies which transaction fields the plugin is permitted to include in
/// a remote-AI suggestion request.
enum RemoteAiField {
  merchant,
  direction,
  kind,
  amountMinor,
  currency,
}

/// Controls whether and how remote-AI suggestions are requested.
final class RemoteAiConfig {
  /// When false, the remote-AI stage is removed from the pipeline entirely
  /// regardless of whether an [ai.task.v1] capability is available.
  final bool enabled;

  /// Consent key that must be granted before transaction context is sent to
  /// remote AI. The plugin checks [ConsentService] at runtime; if the key is
  /// not granted the remote stage is silently skipped.
  final String consentKey;

  /// Fields that may be included in the remote-AI payload. The plugin always
  /// omits balance, phone/account values, and receipt data; this set further
  /// restricts what is sent.
  final Set<RemoteAiField> allowedFields;

  const RemoteAiConfig({
    this.enabled = true,
    this.consentKey = 'tagging.remote_ai',
    this.allowedFields = const {
      RemoteAiField.merchant,
      RemoteAiField.direction,
      RemoteAiField.kind,
      RemoteAiField.amountMinor,
      RemoteAiField.currency,
    },
  });
}

// ─── Root config ─────────────────────────────────────────────────────────────

/// All configuration for the Tagging plugin.
///
/// Pass an instance to [TaggingPlugin]. Every field has a sensible default so
/// a minimal integration requires only:
///
/// ```dart
/// TaggingPlugin(
///   tagDefinitionBox: () => store.box<TagDefinitionEntity>(),
///   tagAssignmentBox: () => store.box<TagAssignmentEntity>(),
///   merchantRuleBox:  () => store.box<MerchantTagRuleEntity>(),
///   operationBox:     () => store.box<TaggingOperationEntity>(),
///   config: TaggingConfig(),
/// )
/// ```
///
/// Apps that replace or extend the tag catalog, supply custom merchant rules,
/// or need different confidence thresholds configure the relevant sub-objects.
final class TaggingConfig {
  // ── Tag catalog ────────────────────────────────────────────────────────────

  /// How the built-in tag catalog is seeded on first install.
  final TagCatalogSeedStrategy catalogSeedStrategy;

  /// Tags supplied by the host app.
  ///
  /// - With [TagCatalogSeedStrategy.replace]: these are the only tags seeded.
  /// - With [TagCatalogSeedStrategy.extend]: merged on top of the built-in
  ///   catalog. Duplicate IDs are skipped.
  /// - With [TagCatalogSeedStrategy.systemOnly]: this list is ignored.
  final List<TagDefinition> initialTags;

  // ── Merchant matching ──────────────────────────────────────────────────────

  /// Keyword-to-tag rules supplied by the host app.
  final List<KeywordTagRule> customMerchantRules;

  /// Where host-supplied merchant rules are evaluated relative to built-in
  /// rules. Ignored when [customMerchantRules] is empty.
  final MerchantRuleStrategy merchantRuleStrategy;

  /// Optional custom function that normalises a merchant name and transaction
  /// type into the key used for rule storage and lookup.
  ///
  /// If null, the built-in normaliser is used:
  ///   `value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim()`
  final String Function(String merchant, String transactionType)?
      merchantKeyNormalizer;

  // ── Inference policy ───────────────────────────────────────────────────────

  /// Confidence thresholds and sensitive-tag IDs governing the pipeline.
  final TaggingConfidenceConfig confidence;

  /// Merchant-history confidence per evidence count.
  final MerchantHistoryConfig merchantHistory;

  // ── Auto-tagging runs ──────────────────────────────────────────────────────

  /// Limits and feature flags for automatic bulk-tagging runs.
  final AutoTagRunConfig autoTagRun;

  // ── Remote AI ──────────────────────────────────────────────────────────────

  /// Controls whether and how remote-AI suggestions are requested.
  final RemoteAiConfig remoteAi;

  // ── Audit and undo ─────────────────────────────────────────────────────────

  /// Undo window and audit-record retention limits.
  final TaggingAuditConfig audit;

  // ── Legacy migration ───────────────────────────────────────────────────────

  /// Set to false to skip the one-time migration of `manual_tags_v1`,
  /// `smart_rules_v1`, and legacy ObjectBox `MerchantTagRecord` rows.
  ///
  /// Set false for apps that are not upgrading from MoneyChat's legacy tag
  /// storage.
  final bool runLegacyMigration;

  // ── Misc ──────────────────────────────────────────────────────────────────

  /// ISO 4217 currency code used as a fallback when a transaction does not
  /// carry an explicit currency. Defaults to 'KES'.
  final String defaultCurrency;

  const TaggingConfig({
    this.catalogSeedStrategy = TagCatalogSeedStrategy.systemOnly,
    this.initialTags = const [],
    this.customMerchantRules = const [],
    this.merchantRuleStrategy = MerchantRuleStrategy.extendBefore,
    this.merchantKeyNormalizer,
    this.confidence = const TaggingConfidenceConfig(),
    this.merchantHistory = const MerchantHistoryConfig(),
    this.autoTagRun = const AutoTagRunConfig(),
    this.remoteAi = const RemoteAiConfig(),
    this.audit = const TaggingAuditConfig(),
    this.runLegacyMigration = true,
    this.defaultCurrency = 'KES',
  });
}
