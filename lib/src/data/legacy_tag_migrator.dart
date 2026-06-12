import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/tagging_models.dart';
import 'tagging_repository.dart';

/// Migrates legacy SharedPreferences tag data into the unified repository.
///
/// Only runs once. Do not remove `manual_tags_v1` until you have verified that
/// counts and sampled assignments match after a full app restart.
final class LegacyTagMigrator {
  final SharedPreferences _legacy;
  final TaggingRepository _target;

  /// Resolves a legacy transaction code (the key in `manual_tags_v1`) to the
  /// stable transaction ID used in the new repository. Return null to skip.
  final String? Function(String transactionCode) resolveTransactionId;

  const LegacyTagMigrator({
    required SharedPreferences legacy,
    required TaggingRepository target,
    required this.resolveTransactionId,
  }) : _legacy = legacy,
       _target = target;

  /// Migrates `manual_tags_v1` entries. Returns the number of assignments
  /// written.
  Future<int> migrateManualAssignments() async {
    final raw = _legacy.getString('manual_tags_v1');
    if (raw == null) return 0;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return 0;

    final now = DateTime.now().toUtc();
    final assignments = <TagAssignment>[];

    for (final entry in decoded.entries) {
      final transactionId = resolveTransactionId(entry.key.toString());
      final tagId = legacyTagNameToId[
          entry.value.toString().toLowerCase().trim()];
      if (transactionId == null || tagId == null) continue;

      final existing = await _target.getAssignment(transactionId);
      if (existing != null) continue;

      assignments.add(
        TagAssignment(
          transactionId: transactionId,
          tagId: tagId,
          source: TagAssignmentSource.manual,
          confidence: 1,
          reasonCode: 'legacy_manual_tag',
          ruleOrModelVersion: 'manual_tags_v1',
          operationId: 'legacy:$transactionId',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    if (assignments.isNotEmpty) {
      final operation = TaggingOperation(
        id: 'legacy_manual_tags_v1',
        decision: const TaggingDecision(
          transactionId: 'migration',
          tagId: 'migration',
          scope: TaggingScope.transactionOnly,
        ),
        previousAssignments: const {},
        createdAt: now,
        reversibleUntil: now,
      );
      await _target.applyOperation(operation, assignments, const []);
    }

    return assignments.length;
  }

  /// Migrates `smart_rules_v1` entries as merchant rules.
  /// Returns the number of rules written.
  Future<int> migrateSmartRules() async {
    final raw = _legacy.getString('smart_rules_v1');
    if (raw == null) return 0;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return 0;

    final now = DateTime.now().toUtc();
    var count = 0;

    for (final entry in decoded.entries) {
      final key = entry.key.toString();
      final tagId =
          legacyTagNameToId[entry.value.toString().toLowerCase().trim()];
      if (tagId == null) continue;

      final ruleWrite = MerchantRuleWrite(
        fingerprint: key,
        direction: 'outgoing',
        tagId: tagId,
        scope: 'futureMatching',
        createdBy: 'legacy_migration',
      );

      // Use an empty operation just to persist the rule.
      final operation = TaggingOperation(
        id: 'legacy_smart_rule_${now.millisecondsSinceEpoch}_$count',
        decision: const TaggingDecision(
          transactionId: 'migration',
          tagId: 'migration',
          scope: TaggingScope.futureMatching,
        ),
        previousAssignments: const {},
        createdAt: now,
        reversibleUntil: now,
      );
      await _target.applyOperation(operation, const [], [ruleWrite]);
      count++;
    }

    return count;
  }
}
