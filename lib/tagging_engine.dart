// Public API barrel for the tagging_engine package.
//
// Import this file in your app:
//   import 'package:tagging_engine/tagging_engine.dart';

// ── Domain & API ──────────────────────────────────────────────────────────────
export 'src/domain/tagging_models.dart';
export 'src/tagging_api.dart';

// ── Configuration (the config file) ──────────────────────────────────────────
export 'src/tagging_config.dart';

// ── Plugin entry point ────────────────────────────────────────────────────────
export 'src/tagging_plugin.dart';

// ── ObjectBox entities (host app must include in its build_runner step) ───────
export 'src/data/tagging_entities.dart';

// ── Legacy migration helper ───────────────────────────────────────────────────
export 'src/data/legacy_tag_migrator.dart';

// ── Host capability interfaces ────────────────────────────────────────────────
// Implement these in your app and pass them to TaggingPlugin / PluginHost.
export 'src/host/transactions_capability.dart';
export 'src/host/ai_task_capability.dart';

// ── Plugin SDK ────────────────────────────────────────────────────────────────
// Bundled so host apps do not need a separate SDK package.
export 'src/sdk/capability_key.dart';
export 'src/sdk/capability_registry.dart';
export 'src/sdk/host_services.dart';
export 'src/sdk/moneychat_plugin.dart';
export 'src/sdk/plugin_event.dart';
export 'src/sdk/plugin_host.dart';
export 'src/sdk/plugin_manifest.dart';
export 'src/sdk/registries.dart';
