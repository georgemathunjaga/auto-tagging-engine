import 'package:objectbox/objectbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data/legacy_tag_migrator.dart';
import 'data/objectbox_tag_repository.dart';
import 'data/tagging_entities.dart';
import 'data/tagging_repository.dart';
import 'domain/tagging_models.dart';
import 'host/ai_task_capability.dart';
import 'host/transactions_capability.dart';
import 'sdk/capability_key.dart';
import 'sdk/moneychat_plugin.dart';
import 'sdk/plugin_host.dart';
import 'sdk/plugin_manifest.dart';
import 'services/candidate_tagger.dart';
import 'services/catalog_service.dart';
import 'services/deterministic_rule_tagger.dart';
import 'services/merchant_fingerprint.dart';
import 'services/merchant_history_tagger.dart';
import 'services/remote_ai_tagger.dart';
import 'services/tagging_confidence_policy.dart';
import 'services/tagging_service.dart';
import 'services/unified_tagging_engine.dart';
import 'services/user_correction_tagger.dart';
import 'tagging_api.dart';
import 'tagging_config.dart';

// Capability keys registered by this plugin.
const _taggingKey = CapabilityKey<TaggingCapability>('tagging.v1');
const _tagCatalogKey = CapabilityKey<TagCatalogCapability>('tag.catalog.v1');

// Keys for capabilities this plugin consumes.
const _transactionsQueryKey =
    CapabilityKey<TransactionsQueryCapability>('transactions.query.v1');
const _aiTaskKey = CapabilityKey<AiTaskCapability>('ai.task.v1');

/// Tagging plugin entry point.
///
/// Construct this in your app's composition root and pass it to your plugin
/// host. Box factories must target an ObjectBox [Store] whose model includes
/// the four tagging entity classes:
///   - [TagDefinitionEntity]
///   - [TagAssignmentEntity]
///   - [MerchantTagRuleEntity]
///   - [TaggingOperationEntity]
///
/// Run `dart run build_runner build` in your app after adding this package as
/// a dependency to regenerate the ObjectBox model.
///
/// Example:
/// ```dart
/// TaggingPlugin(
///   store: store,
///   tagDefinitionBox:  () => store.box<TagDefinitionEntity>(),
///   tagAssignmentBox:  () => store.box<TagAssignmentEntity>(),
///   merchantRuleBox:   () => store.box<MerchantTagRuleEntity>(),
///   operationBox:      () => store.box<TaggingOperationEntity>(),
///   config: TaggingConfig(
///     catalogSeedStrategy: TagCatalogSeedStrategy.systemOnly,
///     remoteAi: RemoteAiConfig(enabled: false),
///   ),
/// )
/// ```
final class TaggingPlugin implements MoneyChatPlugin {
  final Store _store;
  final Box<TagDefinitionEntity> Function() _tagDefinitionBox;
  final Box<TagAssignmentEntity> Function() _tagAssignmentBox;
  final Box<MerchantTagRuleEntity> Function() _merchantRuleBox;
  final Box<TaggingOperationEntity> Function() _operationBox;
  final TaggingConfig _config;

  late ObjectBoxTaggingRepository _repository;

  TaggingPlugin({
    required Store store,
    required Box<TagDefinitionEntity> Function() tagDefinitionBox,
    required Box<TagAssignmentEntity> Function() tagAssignmentBox,
    required Box<MerchantTagRuleEntity> Function() merchantRuleBox,
    required Box<TaggingOperationEntity> Function() operationBox,
    TaggingConfig config = const TaggingConfig(),
  })  : _store = store,
        _tagDefinitionBox = tagDefinitionBox,
        _tagAssignmentBox = tagAssignmentBox,
        _merchantRuleBox = merchantRuleBox,
        _operationBox = operationBox,
        _config = config;

  @override
  PluginManifest get manifest => const PluginManifest(
        id: 'moneychat.tagging',
        version: '1.0.0',
        provides: {'tag.catalog.v1', 'tagging.v1'},
        requires: {'transactions.query.v1'},
        optional: {'ai.task.v1'},
      );

  @override
  Future<void> register(PluginHost host) async {
    const fingerprint = MerchantFingerprint();

    _repository = ObjectBoxTaggingRepository(
      tagDefinitionBox: _tagDefinitionBox(),
      tagAssignmentBox: _tagAssignmentBox(),
      merchantRuleBox: _merchantRuleBox(),
      operationBox: _operationBox(),
      store: _store,
      merchantKeyNormalizer: _config.merchantKeyNormalizer,
    );

    final ai = host.capabilities.optional(_aiTaskKey);
    final transactions =
        host.capabilities.require(_transactionsQueryKey);

    final localTaggers = <CandidateTagger>[
      UserCorrectionTagger(
        repository: _repository,
        fingerprint: fingerprint,
      ),
      MerchantHistoryTagger(
        fingerprint: fingerprint,
        config: _config.merchantHistory,
      ),
      DeterministicRuleTagger(
        fingerprint: fingerprint,
        customRules: _config.customMerchantRules,
        ruleStrategy: _config.merchantRuleStrategy,
      ),
      // On-device (LiteRT) tagger: stub — wire up after model-label versioning.
      // SpendingMemoryTagger: stub — connect spending-profile store when ready.
    ];

    final engine = UnifiedTaggingEngine(
      localTaggers: localTaggers,
      remoteTagger: (_config.remoteAi.enabled && ai != null)
          ? RemoteAiTagger(ai: ai, config: _config.remoteAi)
          : null,
      policy: TaggingConfidencePolicy(config: _config.confidence),
    );

    final service = PluginTaggingService(
      transactions: transactions,
      repository: _repository,
      engine: engine,
      fingerprint: fingerprint,
      contextBuilder: _buildContext,
      config: _config.autoTagRun,
      auditConfig: _config.audit,
    );

    final catalog = PluginTagCatalogService(_repository);

    host.capabilities.provide(
      pluginId: manifest.id,
      key: _taggingKey,
      value: service,
    );
    host.capabilities.provide(
      pluginId: manifest.id,
      key: _tagCatalogKey,
      value: catalog,
    );
  }

  @override
  Future<void> start() async {
    await _seedCatalog();
    if (_config.runLegacyMigration) {
      await _runLegacyMigration();
    }
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _repository.dispose();
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<TaggingContext> _buildContext() async {
    final rules = await _repository.merchantRules();
    final catalog = await _repository.catalog(const TagCatalogQuery());
    return TaggingContext.fromRecords(rules, catalog);
  }

  Future<void> _seedCatalog() async {
    final tagsToSeed = switch (_config.catalogSeedStrategy) {
      TagCatalogSeedStrategy.replace => _config.initialTags,
      TagCatalogSeedStrategy.extend => [
          ...builtInTagCatalog,
          ..._config.initialTags,
        ],
      TagCatalogSeedStrategy.systemOnly => builtInTagCatalog,
    };

    for (final tag in tagsToSeed) {
      final existing = await _repository.getTag(tag.id);
      if (existing == null) {
        await _repository.saveTag(tag);
      }
    }
  }

  Future<void> _runLegacyMigration() async {
    final prefs = await SharedPreferences.getInstance();
    final migrator = LegacyTagMigrator(
      legacy: prefs,
      target: _repository,
      resolveTransactionId: (code) => code,
    );
    await migrator.migrateManualAssignments();
    await migrator.migrateSmartRules();
  }
}
