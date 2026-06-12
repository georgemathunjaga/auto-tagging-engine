import 'package:flutter_test/flutter_test.dart';
import 'package:tagging_engine/tagging_engine.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

final class FixedTagger implements CandidateTagger {
  final TaggingCandidate? _fixed;

  const FixedTagger(this._fixed);

  @override
  String get id => 'fixed.test';

  @override
  Future<TaggingCandidate?> candidate(
    TaggingTransaction transaction,
    TaggingContext context,
  ) async => _fixed;
}

// ── Fixtures ──────────────────────────────────────────────────────────────────

const _groceriesTag = TagDefinition(
  id: 'groceries',
  displayName: 'Groceries',
  classificationId: 'food_dining',
  direction: TagDirection.expense,
  colorToken: 'tag.groceries',
  iconToken: 'icon.groceries',
  source: TagDefinitionSource.builtIn,
);

const _shoppingTag = TagDefinition(
  id: 'shopping',
  displayName: 'Shopping',
  classificationId: 'shopping_lifestyle',
  direction: TagDirection.expense,
  colorToken: 'tag.shopping',
  iconToken: 'icon.shopping',
  source: TagDefinitionSource.builtIn,
);

const _incomeTag = TagDefinition(
  id: 'income',
  displayName: 'Income',
  classificationId: 'income_growth',
  direction: TagDirection.income,
  colorToken: 'tag.income',
  iconToken: 'icon.income',
  source: TagDefinitionSource.builtIn,
);

const _debtTag = TagDefinition(
  id: 'debt',
  displayName: 'Debt',
  classificationId: 'finance_obligations',
  direction: TagDirection.expense,
  colorToken: 'tag.debt',
  iconToken: 'icon.debt',
  source: TagDefinitionSource.builtIn,
);

final _contextWithGroceriesAndShopping = TaggingContext(
  merchantRules: const {},
  spendingMemory: const {},
  catalog: [_groceriesTag, _shoppingTag, _incomeTag, _debtTag],
);

TaggingTransaction _tx({
  String id = 'tx_001',
  String merchant = 'Test Merchant',
  String direction = 'outgoing',
  String kind = 'payment',
}) =>
    TaggingTransaction(
      id: id,
      sourceId: 'mpesa',
      sourceTransactionId: 'OEA001',
      merchant: merchant,
      direction: direction,
      kind: kind,
      amountMinor: 5000,
      currency: 'KES',
      occurredAt: DateTime(2026, 6, 1),
    );

// ── Pipeline priority tests ───────────────────────────────────────────────────

void main() {
  group('UnifiedTaggingEngine — priority ordering', () {
    test('merchant history outranks remote AI', () async {
      final engine = UnifiedTaggingEngine(
        localTaggers: [
          FixedTagger(
            const TaggingCandidate(
              tagId: 'groceries',
              confidence: 0.94,
              source: TagAssignmentSource.merchantHistory,
              reasonCode: 'merchant_history',
            ),
          ),
        ],
        remoteTagger: FixedTagger(
          const TaggingCandidate(
            tagId: 'shopping',
            confidence: 0.99,
            source: TagAssignmentSource.remoteAi,
            reasonCode: 'remote_ai',
          ),
        ),
        policy: const TaggingConfidencePolicy(),
      );

      final result = await engine.suggest(
        TaggingRequest(
          transactions: [_tx(merchant: 'Naivas Supermarket')],
          allowRemoteAi: true,
        ),
        _contextWithGroceriesAndShopping,
      );

      expect(result.suggestions.single.candidate!.tagId, 'groceries');
      expect(result.suggestions.single.action, TaggingAction.autoApply);
    });

    test('remote AI is skipped when allowRemoteAi is false', () async {
      var aiCalled = false;
      final aiTagger = FixedTagger(
        const TaggingCandidate(
          tagId: 'shopping',
          confidence: 0.95,
          source: TagAssignmentSource.remoteAi,
          reasonCode: 'remote_ai',
        ),
      );

      final engine = UnifiedTaggingEngine(
        localTaggers: const [],
        remoteTagger: aiTagger,
        policy: const TaggingConfidencePolicy(),
      );

      final result = await engine.suggest(
        TaggingRequest(transactions: [_tx()], allowRemoteAi: false),
        _contextWithGroceriesAndShopping,
      );

      expect(result.suggestions.single.action, TaggingAction.suppress);
    });

    test('first local tagger wins; later taggers are not consulted', () async {
      var secondCalled = false;

      final engine = UnifiedTaggingEngine(
        localTaggers: [
          FixedTagger(
            const TaggingCandidate(
              tagId: 'groceries',
              confidence: 0.94,
              source: TagAssignmentSource.deterministicRule,
              reasonCode: 'rule_first',
            ),
          ),
          FixedTagger(
            const TaggingCandidate(
              tagId: 'shopping',
              confidence: 0.99,
              source: TagAssignmentSource.deterministicRule,
              reasonCode: 'rule_second',
            ),
          ),
        ],
        remoteTagger: null,
        policy: const TaggingConfidencePolicy(),
      );

      final result = await engine.suggest(
        TaggingRequest(transactions: [_tx()], allowRemoteAi: false),
        _contextWithGroceriesAndShopping,
      );

      expect(result.suggestions.single.candidate!.reasonCode, 'rule_first');
    });

    test('suppress when candidate tagId not in catalog', () async {
      final engine = UnifiedTaggingEngine(
        localTaggers: [
          FixedTagger(
            const TaggingCandidate(
              tagId: 'unknown_tag',
              confidence: 0.95,
              source: TagAssignmentSource.deterministicRule,
              reasonCode: 'rule',
            ),
          ),
        ],
        remoteTagger: null,
        policy: const TaggingConfidencePolicy(),
      );

      final result = await engine.suggest(
        TaggingRequest(transactions: [_tx()], allowRemoteAi: false),
        _contextWithGroceriesAndShopping,
      );

      expect(result.suggestions.single.action, TaggingAction.suppress);
    });
  });

  group('TaggingConfidencePolicy — direction safety', () {
    const policy = TaggingConfidencePolicy();

    test('income tag suppressed for outgoing transaction', () {
      final action = policy.decide(
        _tx(direction: 'outgoing'),
        _incomeTag,
        const TaggingCandidate(
          tagId: 'income',
          confidence: 0.95,
          source: TagAssignmentSource.remoteAi,
          reasonCode: 'remote',
        ),
      );
      expect(action, TaggingAction.suppress);
    });

    test('income tag auto-applied for incoming transaction above threshold', () {
      final action = policy.decide(
        _tx(direction: 'incoming'),
        _incomeTag,
        const TaggingCandidate(
          tagId: 'income',
          confidence: 0.90,
          source: TagAssignmentSource.deterministicRule,
          reasonCode: 'direction_incoming',
        ),
      );
      expect(action, TaggingAction.autoApply);
    });

    test('sensitive tag requires higher threshold', () {
      // debt is sensitive; 0.88 is above autoApplyThreshold (0.85) but below
      // sensitiveAutoApplyThreshold (0.92) → must be suggest, not auto-apply
      final action = policy.decide(
        _tx(direction: 'outgoing'),
        _debtTag,
        const TaggingCandidate(
          tagId: 'debt',
          confidence: 0.88,
          source: TagAssignmentSource.merchantHistory,
          reasonCode: 'merchant_history',
        ),
      );
      expect(action, TaggingAction.suggest);
    });

    test('sensitive tag auto-applied once above sensitiveAutoApplyThreshold',
        () {
      final action = policy.decide(
        _tx(direction: 'outgoing'),
        _debtTag,
        const TaggingCandidate(
          tagId: 'debt',
          confidence: 0.93,
          source: TagAssignmentSource.merchantHistory,
          reasonCode: 'merchant_history',
        ),
      );
      expect(action, TaggingAction.autoApply);
    });

    test('candidate below suggestThreshold is suppressed', () {
      final action = policy.decide(
        _tx(),
        _groceriesTag,
        const TaggingCandidate(
          tagId: 'groceries',
          confidence: 0.50,
          source: TagAssignmentSource.spendingMemory,
          reasonCode: 'spending_memory',
        ),
      );
      expect(action, TaggingAction.suppress);
    });
  });

  group('DeterministicRuleTagger — built-in rules', () {
    const fingerprint = MerchantFingerprint();
    const tagger = DeterministicRuleTagger(fingerprint: fingerprint);

    TaggingContext _ctx() => _contextWithGroceriesAndShopping;

    test('KPLC maps to utilities', () async {
      final utilitiesTag = const TagDefinition(
        id: 'utilities',
        displayName: 'Utilities',
        classificationId: 'housing_utilities',
        direction: TagDirection.expense,
        colorToken: 'tag.utilities',
        iconToken: 'icon.utilities',
        source: TagDefinitionSource.builtIn,
      );
      final context = TaggingContext(
        merchantRules: const {},
        spendingMemory: const {},
        catalog: [utilitiesTag],
      );
      final candidate =
          await tagger.candidate(_tx(merchant: 'KPLC TOKEN'), context);
      expect(candidate?.tagId, 'utilities');
      expect(candidate?.confidence, greaterThanOrEqualTo(0.90));
    });

    test('Naivas maps to groceries', () async {
      final candidate = await tagger.candidate(
        _tx(merchant: 'Naivas Supermarket'),
        _ctx(),
      );
      expect(candidate?.tagId, 'groceries');
    });

    test('unknown merchant returns null', () async {
      final candidate = await tagger.candidate(
        _tx(merchant: 'Random XYZ Corp 9999'),
        _ctx(),
      );
      expect(candidate, isNull);
    });
  });

  group('MerchantHistoryTagger — confidence per evidence count', () {
    const fingerprint = MerchantFingerprint();
    const tagger = MerchantHistoryTagger(fingerprint: fingerprint);

    TaggingContext _ctxWithRule(int count) {
      final tx = _tx(merchant: 'Shell Petrol');
      final key = fingerprint.forTransaction(tx);
      return TaggingContext(
        merchantRules: {
          key: MerchantTagRuleSnapshot(
            tagId: 'fuel',
            evidenceCount: count,
            confidence: 0.78,
            createdBy: 'auto',
          ),
        },
        spendingMemory: const {},
        catalog: [
          const TagDefinition(
            id: 'fuel',
            displayName: 'Fuel',
            classificationId: 'transport_travel',
            direction: TagDirection.expense,
            colorToken: 'tag.fuel',
            iconToken: 'icon.fuel',
            source: TagDefinitionSource.builtIn,
          ),
        ],
      );
    }

    test('single evidence gives 0.78 confidence', () async {
      final candidate = await tagger.candidate(
        _tx(merchant: 'Shell Petrol'),
        _ctxWithRule(1),
      );
      expect(candidate?.confidence, 0.78);
    });

    test('double evidence gives 0.90 confidence', () async {
      final candidate = await tagger.candidate(
        _tx(merchant: 'Shell Petrol'),
        _ctxWithRule(2),
      );
      expect(candidate?.confidence, 0.90);
    });

    test('three or more evidence gives 0.94 confidence', () async {
      final candidate = await tagger.candidate(
        _tx(merchant: 'Shell Petrol'),
        _ctxWithRule(5),
      );
      expect(candidate?.confidence, 0.94);
    });

    test('no matching rule returns null', () async {
      final candidate = await tagger.candidate(
        _tx(merchant: 'Unknown Merchant'),
        TaggingContext(
          merchantRules: const {},
          spendingMemory: const {},
          catalog: const [],
        ),
      );
      expect(candidate, isNull);
    });
  });

  group('MerchantFingerprint', () {
    const fp = MerchantFingerprint();

    test('same transaction produces same fingerprint', () {
      final tx = _tx(merchant: 'Naivas Westlands');
      expect(fp.forTransaction(tx), fp.forTransaction(tx));
    });

    test('different merchants produce different fingerprints', () {
      final a = _tx(merchant: 'Naivas Westlands');
      final b = _tx(merchant: 'Carrefour Junction');
      expect(fp.forTransaction(a), isNot(fp.forTransaction(b)));
    });

    test('normalize strips non-alphanumeric characters', () {
      expect(fp.normalize('Naivas!! Westlands ##'), 'naivas westlands');
    });
  });

  group('TagCatalogQuery', () {
    test('default query has no filters', () {
      const query = TagCatalogQuery();
      expect(query.direction, isNull);
      expect(query.includeDeprecated, false);
    });

    test('direction filter is preserved', () {
      const query = TagCatalogQuery(direction: TagDirection.income);
      expect(query.direction, TagDirection.income);
    });
  });

  group('TaggingConfig — defaults', () {
    test('default config uses systemOnly seed strategy', () {
      const config = TaggingConfig();
      expect(
        config.catalogSeedStrategy,
        TagCatalogSeedStrategy.systemOnly,
      );
    });

    test('default currency is KES', () {
      const config = TaggingConfig();
      expect(config.defaultCurrency, 'KES');
    });

    test('legacy migration is on by default', () {
      const config = TaggingConfig();
      expect(config.runLegacyMigration, true);
    });

    test('remote AI is enabled by default', () {
      const config = TaggingConfig();
      expect(config.remoteAi.enabled, true);
    });

    test('sensitive tag IDs include debt, loan, health', () {
      const config = TaggingConfig();
      expect(config.confidence.sensitiveTagIds, containsAll(['debt', 'loan', 'health']));
    });
  });

  group('legacyTagNameToId mapping', () {
    test('all 31 legacy names resolve', () {
      expect(legacyTagNameToId.length, 31);
    });

    test('food & dining resolves to food_dining', () {
      expect(legacyTagNameToId['food & dining'], 'food_dining');
    });

    test('data/bundles resolves to data_bundles', () {
      expect(legacyTagNameToId['data/bundles'], 'data_bundles');
    });

    test('fuel (etims) resolves to fuel_etims', () {
      expect(legacyTagNameToId['fuel (etims)'], 'fuel_etims');
    });
  });
}
