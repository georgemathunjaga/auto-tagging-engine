import '../domain/tagging_models.dart';
import '../tagging_config.dart';
import 'candidate_tagger.dart';
import 'merchant_fingerprint.dart';

final class DeterministicRuleTagger implements CandidateTagger {
  final MerchantFingerprint _fingerprint;
  final List<KeywordTagRule> _customRules;
  final MerchantRuleStrategy _strategy;

  const DeterministicRuleTagger({
    required MerchantFingerprint fingerprint,
    List<KeywordTagRule> customRules = const [],
    MerchantRuleStrategy ruleStrategy = MerchantRuleStrategy.extendBefore,
  })  : _fingerprint = fingerprint,
        _customRules = customRules,
        _strategy = ruleStrategy;

  @override
  String get id => 'deterministic_rules.v1';

  @override
  Future<TaggingCandidate?> candidate(
    TaggingTransaction transaction,
    TaggingContext context,
  ) async {
    final merchant = _fingerprint.normalize(transaction.merchant);
    final kind = transaction.kind.toLowerCase();
    final combined = '$merchant $kind';

    if (_strategy == MerchantRuleStrategy.extendBefore) {
      final custom = _matchCustom(combined, context);
      if (custom != null) return custom;
    }

    final builtin = _matchBuiltIn(merchant, transaction.direction, context);
    if (builtin != null) return builtin;

    if (_strategy == MerchantRuleStrategy.extendAfter) {
      return _matchCustom(combined, context);
    }

    return null;
  }

  TaggingCandidate? _matchCustom(
    String combined,
    TaggingContext context,
  ) {
    for (final rule in _customRules) {
      final hit = rule.keywords.any((kw) => combined.contains(kw));
      if (hit && context.catalog.any((t) => t.id == rule.tagId)) {
        return TaggingCandidate(
          tagId: rule.tagId,
          confidence: rule.confidence,
          source: TagAssignmentSource.deterministicRule,
          reasonCode: 'custom_keyword',
          version: id,
        );
      }
    }
    return null;
  }

  TaggingCandidate? _matchBuiltIn(
    String merchant,
    String direction,
    TaggingContext context,
  ) {
    final rule = switch (merchant) {
      // Utilities
      final v when v.contains('kplc') => ('utilities', 0.96, 'merchant_kplc'),
      final v when v.contains('kenya power') =>
        ('utilities', 0.96, 'merchant_kplc'),
      final v when v.contains('zuku') => ('utilities', 0.92, 'merchant_isp'),
      final v when v.contains('safaricom home') =>
        ('utilities', 0.92, 'merchant_isp'),

      // Groceries / supermarkets
      final v
          when v.contains('naivas') ||
              v.contains('carrefour') ||
              v.contains('quickmart') ||
              v.contains('chandarana') ||
              v.contains('cleanshelf') =>
        ('groceries', 0.94, 'merchant_supermarket'),

      // Food & dining
      final v
          when v.contains('kfc') ||
              v.contains('java') ||
              v.contains('artcaffe') ||
              v.contains('chicken inn') ||
              v.contains('debonairs') =>
        ('food_dining', 0.92, 'merchant_restaurant'),

      // Transport
      final v
          when v.contains('uber') ||
              v.contains('bolt') ||
              v.contains('little cab') =>
        ('transport', 0.92, 'merchant_rideshare'),

      // Fuel
      final v
          when v.contains('shell') ||
              v.contains('total') ||
              v.contains('rubis') ||
              v.contains('vivo energy') ||
              v.contains('galana') =>
        ('fuel', 0.90, 'merchant_fuel_station'),

      // Airtime / data
      final v
          when v.contains('safaricom') &&
              !v.contains('home') &&
              !v.contains('fibre') =>
        ('airtime', 0.88, 'merchant_telco_airtime'),

      // Subscriptions
      final v
          when v.contains('netflix') ||
              v.contains('spotify') ||
              v.contains('dstv') ||
              v.contains('showmax') =>
        ('subscriptions', 0.94, 'merchant_subscription'),

      // Loan / Fuliza
      final v when v.contains('fuliza') =>
        ('loan', 0.95, 'merchant_fuliza'),
      final v when v.contains('mshwari') =>
        ('savings', 0.92, 'merchant_mshwari'),

      // Income heuristic for incoming
      _ when direction == 'incoming' =>
        ('income', 0.65, 'direction_incoming'),

      _ => null,
    };

    if (rule == null) return null;
    final (tagId, confidence, reasonCode) = rule;
    if (!context.catalog.any((t) => t.id == tagId)) return null;
    return TaggingCandidate(
      tagId: tagId,
      confidence: confidence,
      source: TagAssignmentSource.deterministicRule,
      reasonCode: reasonCode,
      version: id,
    );
  }
}
