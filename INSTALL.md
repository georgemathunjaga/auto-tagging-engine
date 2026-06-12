# Tagging Engine — Installation & Integration Guide

The `tagging_engine` package provides a complete, self-contained tagging plugin
for any MoneyChat-compatible Flutter app. It manages the tag catalog, manual
and propagated tagging, a local inference pipeline, and optional remote-AI
suggestions.

---

## Contents

1. [Prerequisites](#1-prerequisites)
2. [Add the dependency](#2-add-the-dependency)
3. [ObjectBox setup](#3-objectbox-setup)
4. [Wire up the plugin host](#4-wire-up-the-plugin-host)
5. [Implement host capability interfaces](#5-implement-host-capability-interfaces)
6. [Register the plugin](#6-register-the-plugin)
7. [Configuration reference](#7-configuration-reference)
8. [Using the capabilities](#8-using-the-capabilities)
9. [Migrating from legacy MoneyChat storage](#9-migrating-from-legacy-moneychat-storage)
10. [Running the tests](#10-running-the-tests)
11. [Troubleshooting](#11-troubleshooting)

---

## 1. Prerequisites

| Requirement | Version |
|---|---|
| Dart SDK | `>=3.3.0 <4.0.0` |
| Flutter | `>=3.22.0` |
| ObjectBox | `^5.2.0` |
| Your app already uses ObjectBox | see [ObjectBox docs](https://docs.objectbox.io/flutter) |

---

## 2. Add the dependency

### Path dependency (monorepo / local checkout)

Add the following to your app's `pubspec.yaml`:

```yaml
dependencies:
  tagging_engine:
    path: ../tagging_engine   # adjust the relative path as needed
```

Then fetch it:

```bash
flutter pub get
```

### Git dependency (shared repository)

```yaml
dependencies:
  tagging_engine:
    git:
      url: https://github.com/your-org/tagging_engine.git
      ref: main
```

---

## 3. ObjectBox setup

The plugin defines four ObjectBox entity classes. Your app's `build_runner`
step must pick them up so they are included in your generated `Store`.

### 3a. Add `objectbox_generator` to your dev dependencies (if not already)

```yaml
dev_dependencies:
  objectbox_generator: ^5.2.0
  build_runner: ^2.4.0
```

### 3b. Regenerate your ObjectBox model

```bash
dart run build_runner build --delete-conflicting-outputs
```

This command scans all `lib/` directories, including those in path/git
dependencies. It finds the four annotated entity classes:

| Entity class | Purpose |
|---|---|
| `TagDefinitionEntity` | Tag catalog — built-in, system, and custom tags |
| `TagAssignmentEntity` | One assignment per transaction (the source of truth) |
| `MerchantTagRuleEntity` | Merchant-fingerprint → tag rules used by inference |
| `TaggingOperationEntity` | Audit log of every bulk operation; enables undo |

After generation your `objectbox.g.dart` will include a model entry for each.

### 3c. Verify generation

Open `lib/objectbox.g.dart` and confirm the four entity names appear in
`_entities`:

```dart
final _entities = <ModelEntity>[
  // ...
  _TagDefinitionEntity,
  _TagAssignmentEntity,
  _MerchantTagRuleEntity,
  _TaggingOperationEntity,
];
```

---

## 4. Wire up the plugin host

The plugin communicates with your app through a `PluginHost`. If your app
already has one, skip to step 5. If you are setting up the plugin system for
the first time:

```dart
import 'package:tagging_engine/tagging_engine.dart';

// Create once at app startup and keep alive for the app's lifetime.
final pluginHost = PluginHost(
  capabilities:    CapabilityRegistry(),
  events:          PluginEventBus(),
  routes:          RouteRegistry(),
  serviceCards:    ServiceCardRegistry(),
  backgroundTasks: BackgroundTaskRegistry(),
  secrets:         YourSecureSecretStore(),       // implements SecureSecretStore
  preferences:     YourKeyValueStore(),           // implements NamespacedKeyValueStore
  consent:         YourConsentService(),          // implements ConsentService
  subscriptions:   YourSubscriptionCapabilities(), // implements SubscriptionCapabilities
  telemetry:       YourTelemetrySink(),           // implements TelemetrySink
);
```

Minimal no-op implementations are fine for a quick start:

```dart
class NoOpTelemetry implements TelemetrySink {
  @override void count(String name, {Map<String, String> dimensions = const {}}) {}
  @override void timing(String name, Duration duration, {Map<String, String> dimensions = const {}}) {}
  @override void error(String name, Object error, {StackTrace? stackTrace, Map<String, String> dimensions = const {}}) {}
}
```

---

## 5. Implement host capability interfaces

The tagging engine reads transaction data through an abstract interface so it
stays decoupled from your persistence layer.

### 5a. `TransactionsQueryCapability`

Implement this to let the plugin look up and page through transactions:

```dart
import 'package:tagging_engine/tagging_engine.dart';

class MyTransactionRecord implements TransactionRecord {
  @override final String id;
  @override final String sourceId;
  @override final String sourceTransactionId;
  @override final TransactionCounterparty counterparty;
  @override final TransactionDirection direction;
  @override final TransactionKind kind;
  @override final int amountMinor;
  @override final String currency;
  @override final DateTime occurredAt;
  @override final String merchantFingerprint;

  const MyTransactionRecord({
    required this.id,
    required this.sourceId,
    required this.sourceTransactionId,
    required this.counterparty,
    required this.direction,
    required this.kind,
    required this.amountMinor,
    required this.currency,
    required this.occurredAt,
    required this.merchantFingerprint,
  });
}

class MyTransactionsService implements TransactionsQueryCapability {
  @override
  Future<TransactionRecord?> get(String transactionId) async {
    // Query your data source and return a MyTransactionRecord.
    final row = await myDb.findTransaction(transactionId);
    return row == null ? null : MyTransactionRecord.fromRow(row);
  }

  @override
  Future<TransactionPage> page(TransactionQuery query) async {
    final rows = await myDb.queryTransactions(
      merchantFingerprint: query.merchantFingerprint,
      from: query.from,
      to: query.to,
      limit: query.limit,
    );
    return TransactionPage(
      items: rows.map(MyTransactionRecord.fromRow).toList(),
      hasMore: rows.length == query.limit,
    );
  }
}
```

Register the implementation as the `transactions.query.v1` capability
**before** registering the tagging plugin:

```dart
pluginHost.capabilities.provide(
  pluginId: 'moneychat.transactions',
  key: const CapabilityKey<TransactionsQueryCapability>('transactions.query.v1'),
  value: MyTransactionsService(),
);
```

### 5b. `AiTaskCapability` (optional)

Only required if you want the remote-AI suggestion stage. Skip and set
`RemoteAiConfig(enabled: false)` in `TaggingConfig` if you do not need it.

```dart
class MyAiService implements AiTaskCapability {
  @override
  Future<AiTaskResult<T>> run<T>(AiTask<T> task) async {
    // Call your AI backend and decode the response.
    try {
      final raw = await myAiBackend.complete(task.type, task.input);
      return AiTaskSuccess(task.decode(raw));
    } catch (e) {
      return AiTaskFailure(e.toString());
    }
  }
}

// Register before the tagging plugin:
pluginHost.capabilities.provide(
  pluginId: 'moneychat.ai',
  key: const CapabilityKey<AiTaskCapability>('ai.task.v1'),
  value: MyAiService(),
);
```

---

## 6. Register the plugin

In your app's composition root (e.g. `main.dart` or a dedicated
`AppBootstrapper`), create the `TaggingPlugin` and register it with the host:

```dart
import 'package:tagging_engine/tagging_engine.dart';

// store is your ObjectBox Store, opened with the generated openStore().
final taggingPlugin = TaggingPlugin(
  store: store,
  tagDefinitionBox:  () => store.box<TagDefinitionEntity>(),
  tagAssignmentBox:  () => store.box<TagAssignmentEntity>(),
  merchantRuleBox:   () => store.box<MerchantTagRuleEntity>(),
  operationBox:      () => store.box<TaggingOperationEntity>(),
  config: const TaggingConfig(),   // all defaults — see section 7
);

// 1. Register capabilities.
await taggingPlugin.register(pluginHost);

// 2. Start the plugin (seeds catalog, runs legacy migration if enabled).
await taggingPlugin.start();

// 3. Keep a reference for orderly shutdown.
//    Call taggingPlugin.stop() then taggingPlugin.dispose() on app exit.
```

### Full startup example

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = await openStore(); // generated by build_runner

  final host = PluginHost(
    capabilities:    CapabilityRegistry(),
    events:          PluginEventBus(),
    routes:          RouteRegistry(),
    serviceCards:    ServiceCardRegistry(),
    backgroundTasks: BackgroundTaskRegistry(),
    secrets:         SecureStorageAdapter(),
    preferences:     SharedPreferencesAdapter(),
    consent:         AppConsentService(),
    subscriptions:   AppSubscriptionService(),
    telemetry:       FirebaseTelemetry(),
  );

  // Register upstream capabilities first.
  host.capabilities.provide(
    pluginId: 'moneychat.transactions',
    key: const CapabilityKey<TransactionsQueryCapability>('transactions.query.v1'),
    value: MyTransactionsService(store),
  );

  // Register the tagging plugin.
  final tagging = TaggingPlugin(
    store: store,
    tagDefinitionBox:  () => store.box<TagDefinitionEntity>(),
    tagAssignmentBox:  () => store.box<TagAssignmentEntity>(),
    merchantRuleBox:   () => store.box<MerchantTagRuleEntity>(),
    operationBox:      () => store.box<TaggingOperationEntity>(),
    config: const TaggingConfig(),
  );
  await tagging.register(host);
  await tagging.start();

  runApp(MyApp(host: host, store: store));
}
```

---

## 7. Configuration reference

All configuration lives in `TaggingConfig`. Every field has a sensible default.

```dart
TaggingConfig(
  // ── Tag catalog ──────────────────────────────────────────────────────────
  catalogSeedStrategy: TagCatalogSeedStrategy.systemOnly,
  // systemOnly  → seed the 31 built-in MoneyChat tags (default)
  // extend      → built-in tags + your initialTags merged
  // replace     → only your initialTags; built-ins are not seeded

  initialTags: const [],             // your custom TagDefinition list

  // ── Merchant matching ────────────────────────────────────────────────────
  customMerchantRules: const [],     // List<KeywordTagRule>
  merchantRuleStrategy: MerchantRuleStrategy.extendBefore,
  // extendBefore  → your rules evaluated first (default)
  // extendAfter   → your rules evaluated after built-ins
  // replaceDefaults → only your rules; built-ins are ignored

  merchantKeyNormalizer: null,       // optional custom String Function(merchant, type)

  // ── Inference confidence ─────────────────────────────────────────────────
  confidence: TaggingConfidenceConfig(
    suggestThreshold:            0.60,  // below → suppressed
    autoApplyThreshold:          0.85,  // at or above → auto-applied (normal tags)
    sensitiveAutoApplyThreshold: 0.92,  // at or above → auto-applied (sensitive tags)
    sensitiveTagIds: {'debt', 'loan', 'health'},
  ),

  // ── Merchant history ─────────────────────────────────────────────────────
  merchantHistory: MerchantHistoryConfig(
    singleEvidenceConfidence: 0.78,
    doubleEvidenceConfidence: 0.90,
    strongEvidenceConfidence: 0.94,
    recentEvidenceWindow: Duration(hours: 72),
  ),

  // ── Auto-tagging runs ────────────────────────────────────────────────────
  autoTagRun: AutoTagRunConfig(
    maximumAutoApply:           30,
    allowSpendingMemory:        true,
    spendingMemoryConfidenceCap: 0.82,
  ),

  // ── Remote AI ────────────────────────────────────────────────────────────
  remoteAi: RemoteAiConfig(
    enabled:    true,
    consentKey: 'tagging.remote_ai',
    allowedFields: {
      RemoteAiField.merchant,
      RemoteAiField.direction,
      RemoteAiField.kind,
      RemoteAiField.amountMinor,
      RemoteAiField.currency,
    },
  ),

  // ── Audit and undo ───────────────────────────────────────────────────────
  audit: TaggingAuditConfig(
    undoWindow:      Duration(days: 30),
    maxAuditRecords: 250,
  ),

  // ── Legacy migration ─────────────────────────────────────────────────────
  runLegacyMigration: true,   // set false for apps not upgrading from legacy

  // ── Misc ─────────────────────────────────────────────────────────────────
  defaultCurrency: 'KES',
)
```

### Common configuration recipes

**Disable remote AI entirely:**

```dart
TaggingConfig(
  remoteAi: RemoteAiConfig(enabled: false),
)
```

**Supply your own tag catalog and ignore the built-ins:**

```dart
TaggingConfig(
  catalogSeedStrategy: TagCatalogSeedStrategy.replace,
  initialTags: myAppTags,   // List<TagDefinition>
)
```

**Add custom merchant keyword rules:**

```dart
TaggingConfig(
  customMerchantRules: [
    KeywordTagRule(
      keywords: {'quickmart', 'chandarana'},
      tagId: 'groceries',
      confidence: 0.90,
    ),
    KeywordTagRule(
      keywords: {'parklands spa', 'the hub'},
      tagId: 'entertainment',
      confidence: 0.85,
    ),
  ],
  merchantRuleStrategy: MerchantRuleStrategy.extendBefore,
)
```

**New app (no legacy migration needed):**

```dart
TaggingConfig(runLegacyMigration: false)
```

---

## 8. Using the capabilities

Retrieve capabilities from the registry after the plugin is registered:

```dart
final taggingCap = pluginHost.capabilities.require(
  const CapabilityKey<TaggingCapability>('tagging.v1'),
);

final catalogCap = pluginHost.capabilities.require(
  const CapabilityKey<TagCatalogCapability>('tag.catalog.v1'),
);
```

### Watch the tag catalog

```dart
catalogCap
    .watchCatalog(const TagCatalogQuery())
    .listen((tags) {
      // Rebuild your tag picker UI.
    });
```

### Tag a single transaction (manual, this transaction only)

```dart
final operation = await taggingCap.apply(
  TaggingDecision(
    transactionId: 'tx_001',
    tagId: 'groceries',
    scope: TaggingScope.transactionOnly,
  ),
);
```

### Preview before applying to matching transactions

```dart
// Show the user how many transactions will be affected.
final preview = await taggingCap.preview(
  TaggingDecision(
    transactionId: 'tx_001',
    tagId: 'groceries',
    scope: TaggingScope.matchingUntagged,
  ),
);

print('Will tag ${preview.affectedTransactionIds.length} transactions '
      '(${preview.alreadyTaggedCount} already tagged)');
print('Earliest: ${preview.earliest}, Latest: ${preview.latest}');

// User confirms → apply.
final operation = await taggingCap.apply(
  TaggingDecision(
    transactionId: 'tx_001',
    tagId: 'groceries',
    scope: TaggingScope.matchingUntagged,
  ),
);
```

### Tagging scopes

| Scope | Behaviour |
|---|---|
| `transactionOnly` | Tags only the selected transaction |
| `matchingUntagged` | Tags all untagged transactions with the same merchant fingerprint |
| `allMatching` | Tags all matching transactions, including already-tagged ones |
| `futureMatching` | Same as `allMatching` + saves a merchant rule for future transactions |

### Undo a bulk operation

```dart
await taggingCap.undo(operation.id);
// Operations are undoable for TaggingAuditConfig.undoWindow (default 30 days).
```

### Watch a single assignment

```dart
taggingCap.watchAssignment('tx_001').listen((assignment) {
  if (assignment == null) {
    print('Untagged');
  } else {
    print('Tag: ${assignment.tagId}, source: ${assignment.source.name}');
  }
});
```

### Get AI/local suggestions without applying

```dart
final suggestions = await taggingCap.suggest(
  TaggingRequest(
    transactions: [myTaggingTransaction],
    allowRemoteAi: true,
  ),
);

for (final s in suggestions.suggestions) {
  print('${s.transaction.merchant} → ${s.candidate?.tagId} '
        '(${s.action.name}, confidence: ${s.candidate?.confidence})');
}
```

### Run auto-tagging on a batch

```dart
final run = await taggingCap.autoTag(
  AutoTagRequest(
    transactionIds: untaggedIds,
    allowRemoteAi: false,
    maximumAutoApply: 30,
  ),
);

print('Considered: ${run.considered}');
print('Applied: ${run.applied}');
print('Suggested (needs user confirmation): ${run.suggested}');
print('Suppressed (low confidence): ${run.suppressed}');
```

### Create a custom tag

```dart
final tag = await catalogCap.createCustomTag(
  CreateTagRequest(
    displayName: 'Side Hustle',
    classificationId: 'business_operations',
    direction: TagDirection.income,
    colorToken: 'tag.custom_green',
    iconToken: 'icon.briefcase',
  ),
);
// tag.id == 'custom.side_hustle'
```

### Deprecate a custom tag

```dart
await catalogCap.deprecateCustomTag(
  'custom.side_hustle',
  replacementTagId: 'business',   // optional — helps UX guide users
);
```

---

## 9. Migrating from legacy MoneyChat storage

If your app is upgrading from the legacy MoneyChat tag storage
(`manual_tags_v1` and `smart_rules_v1` in SharedPreferences), set
`runLegacyMigration: true` in `TaggingConfig` (this is the default).

The plugin runs the migration automatically on first `start()`. It:

1. Reads `manual_tags_v1` and converts each entry to a `TagAssignment`.
2. Reads `smart_rules_v1` and converts each entry to a `MerchantTagRuleEntity`.
3. Skips entries that already have an assignment in the new repository.
4. Never deletes the legacy keys — they remain until you are confident the
   migration is complete.

### Supplying a custom transaction-ID resolver

The legacy storage keys transactions by their M-PESA transaction code, while
the new repository uses stable UUIDs. Provide a resolver if your app has a
mapping:

```dart
// In tagging_plugin.dart start() the default resolver is (code) => code.
// To override, subclass TaggingPlugin or call the migrator directly:

final prefs = await SharedPreferences.getInstance();
final migrator = LegacyTagMigrator(
  legacy: prefs,
  target: yourRepository,
  resolveTransactionId: (code) {
    // Look up the stable UUID for this legacy code.
    return myTransactionIndex.findById(code);
  },
);

final migrated = await migrator.migrateManualAssignments();
print('Migrated $migrated manual assignments');
await migrator.migrateSmartRules();
```

### Removing legacy keys

Only remove the legacy SharedPreferences keys after you have verified that:

- The total assignment count in the new repository matches the count in
  `manual_tags_v1`.
- A sampled set of assignments resolves correctly from the new catalog.
- The app has restarted at least once with the new repository as the sole
  source of truth.

```dart
// After verification:
final prefs = await SharedPreferences.getInstance();
await prefs.remove('manual_tags_v1');
await prefs.remove('smart_rules_v1');
```

---

## 10. Running the tests

From the `tagging_engine` package root:

```bash
flutter test
```

The test suite covers:

- Pipeline priority (local taggers outrank remote AI)
- Direction-safety suppression (income tag on outgoing transaction)
- Confidence boundaries (suggest vs auto-apply vs suppress)
- Sensitive-tag threshold enforcement (debt, loan, health)
- Deterministic rule matching (KPLC, Naivas, unknown merchant)
- Merchant-history confidence per evidence count
- `MerchantFingerprint` determinism and normalization
- `TaggingConfig` defaults and `legacyTagNameToId` completeness

---

## 11. Troubleshooting

### `StateError: Required capability transactions.query.v1 is unavailable`

The transactions capability must be registered **before** calling
`taggingPlugin.register(host)`. Move your
`host.capabilities.provide(... 'transactions.query.v1' ...)` call earlier in
your startup sequence.

### `build_runner` does not include the entity classes

Ensure the `tagging_engine` package is listed in `pubspec.yaml` **before**
running `build_runner`. Run `flutter pub get` first, then:

```bash
dart run build_runner build --delete-conflicting-outputs
```

If using a fork of `objectbox_flutter_libs`, confirm the fork's
`objectbox_generator` version matches the `objectbox` version in `tagging_engine/pubspec.yaml`.

### Assignment reads return `null` after `apply()`

`apply()` is atomic within a single `Store.runInTransaction`. If the call
returns without throwing, the write succeeded. A `null` read usually means
the `transactionId` you are querying does not match the one passed to
`apply()`. Double-check that your `TransactionsQueryCapability.get()` returns
a record whose `id` field matches the ID used in `TaggingDecision`.

### Undo throws `StateError: The undo period has expired`

The default undo window is 30 days (`TaggingAuditConfig.undoWindow`). Increase
it in config if your app needs longer:

```dart
TaggingConfig(
  audit: TaggingAuditConfig(undoWindow: Duration(days: 90)),
)
```

### Remote AI suggestions are never returned

1. Check that `RemoteAiConfig(enabled: true)` is set.
2. Confirm an `AiTaskCapability` is registered under `ai.task.v1` **before**
   `taggingPlugin.register(host)`.
3. Verify that your `ConsentService.isGranted(config.remoteAi.consentKey, 1)`
   returns `true` for the user. The plugin silently skips the AI stage if
   consent is not granted.
4. Confirm `TaggingRequest(allowRemoteAi: true)` is passed at the call site.

---

## Built-in tag catalog

The plugin seeds the following 31 tags when
`TagCatalogSeedStrategy.systemOnly` or `extend` is used:

| Tag ID | Display name | Classification | Direction |
|---|---|---|---|
| `income` | Income | Income & Growth | income |
| `investment` | Investment | Income & Growth | expense |
| `savings` | Savings | Income & Growth | expense |
| `salary` | Salary | Income & Growth | income |
| `groceries` | Groceries | Food & Dining | expense |
| `food_dining` | Food & Dining | Food & Dining | expense |
| `shopping` | Shopping | Shopping & Lifestyle | expense |
| `transport` | Transport | Transport & Travel | expense |
| `utilities` | Utilities | Housing & Utilities | expense |
| `bills` | Bills | Housing & Utilities | expense |
| `rent` | Rent | Housing & Utilities | expense |
| `fuel` | Fuel | Transport & Travel | expense |
| `airtime` | Airtime | Telecom & Subscriptions | expense |
| `minutes` | Minutes | Telecom & Subscriptions | expense |
| `data_bundles` | Data/Bundles | Telecom & Subscriptions | expense |
| `loan` | Loan | Finance & Obligations | neutral |
| `loan_repayment` | Loan Repayment | Finance & Obligations | expense |
| `insurance` | Insurance | Finance & Obligations | expense |
| `subscriptions` | Subscriptions | Telecom & Subscriptions | expense |
| `transfer` | Transfer | Finance & Obligations | neutral |
| `debt` | Debt | Finance & Obligations | expense |
| `entertainment` | Entertainment | Entertainment & Leisure | expense |
| `health` | Health | Health & Wellness | expense |
| `education` | Education | Education & Growth | expense |
| `personal` | Personal | Other | expense |
| `gifts` | Gifts | Other | expense |
| `vacation` | Vacation | Transport & Travel | expense |
| `business` | Business | Business Operations | neutral |
| `business_meetings` | Business Meetings | Business Operations | expense |
| `fuel_etims` | Fuel (eTIMS) | Business Operations | expense |
| `other_business` | Other Business | Business Operations | expense |
| `other` | Other | Other | neutral |

Sensitive tags (require `sensitiveAutoApplyThreshold` before auto-apply):
`debt`, `loan`, `health`.
