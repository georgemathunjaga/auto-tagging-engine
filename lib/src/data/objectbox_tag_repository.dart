import 'dart:async';
import 'dart:convert';

import 'package:objectbox/objectbox.dart';

import '../domain/tagging_models.dart';
import '../tagging_api.dart';
import 'tagging_entities.dart';
import 'tagging_repository.dart';

final class ObjectBoxTaggingRepository implements TaggingRepository {
  final Box<TagDefinitionEntity> _tagDefinitionBox;
  final Box<TagAssignmentEntity> _tagAssignmentBox;
  final Box<MerchantTagRuleEntity> _merchantRuleBox;
  final Box<TaggingOperationEntity> _operationBox;
  final Store _store;
  final String Function(String merchant, String transactionType)?
      _merchantKeyNormalizer;

  final _catalogChangeController = StreamController<void>.broadcast();
  final Map<String, StreamController<TagAssignment?>> _assignmentStreams = {};

  ObjectBoxTaggingRepository({
    required Box<TagDefinitionEntity> tagDefinitionBox,
    required Box<TagAssignmentEntity> tagAssignmentBox,
    required Box<MerchantTagRuleEntity> merchantRuleBox,
    required Box<TaggingOperationEntity> operationBox,
    required Store store,
    String Function(String merchant, String transactionType)?
        merchantKeyNormalizer,
  })  : _tagDefinitionBox = tagDefinitionBox,
        _tagAssignmentBox = tagAssignmentBox,
        _merchantRuleBox = merchantRuleBox,
        _operationBox = operationBox,
        _store = store,
        _merchantKeyNormalizer = merchantKeyNormalizer;

  // ── Assignments ────────────────────────────────────────────────────────────

  @override
  Stream<TagAssignment?> watchAssignment(String transactionId) {
    return _assignmentStreams
        .putIfAbsent(
          transactionId,
          () => StreamController<TagAssignment?>.broadcast(),
        )
        .stream;
  }

  @override
  Future<TagAssignment?> getAssignment(String transactionId) async {
    final entity = _tagAssignmentBox
        .query(TagAssignmentEntity_.transactionId.equals(transactionId))
        .build()
        .findFirst();
    return entity == null ? null : _mapAssignment(entity);
  }

  @override
  Future<List<TagAssignment>> getAssignments(
    Iterable<String> transactionIds,
  ) async {
    final ids = transactionIds.toList();
    if (ids.isEmpty) return [];
    final entities = _tagAssignmentBox
        .query(TagAssignmentEntity_.transactionId.oneOf(ids))
        .build()
        .find();
    return entities.map(_mapAssignment).toList(growable: false);
  }

  // ── Catalog ────────────────────────────────────────────────────────────────

  @override
  Stream<void> watchCatalogChanges() => _catalogChangeController.stream;

  @override
  Future<List<TagDefinition>> catalog(TagCatalogQuery query) async {
    var qb = _tagDefinitionBox.query();
    if (!query.includeDeprecated) {
      qb = qb..and(TagDefinitionEntity_.status.equals('active'));
    }
    if (query.direction != null) {
      qb = qb..and(TagDefinitionEntity_.direction.equals(query.direction!.name));
    }
    final entities = qb.build().find();
    return entities.map(_mapTagDefinition).toList(growable: false);
  }

  @override
  Future<TagDefinition?> getTag(String id) async {
    final entity = _tagDefinitionBox
        .query(TagDefinitionEntity_.tagId.equals(id))
        .build()
        .findFirst();
    return entity == null ? null : _mapTagDefinition(entity);
  }

  @override
  Future<void> saveTag(TagDefinition tag) async {
    final existing = _tagDefinitionBox
        .query(TagDefinitionEntity_.tagId.equals(tag.id))
        .build()
        .findFirst();
    final entity = _mapTagDefinitionToEntity(tag, existing?.objectBoxId ?? 0);
    _tagDefinitionBox.put(entity);
    _catalogChangeController.add(null);
  }

  // ── Merchant rules ─────────────────────────────────────────────────────────

  @override
  Future<List<MerchantRuleRecord>> merchantRules() async {
    final entities = _merchantRuleBox.getAll();
    return entities.map(_mapMerchantRule).toList(growable: false);
  }

  @override
  Future<MerchantRuleRecord?> getMerchantRule(String fingerprint) async {
    final entity = _merchantRuleBox
        .query(
          MerchantTagRuleEntity_.merchantFingerprint.equals(fingerprint),
        )
        .build()
        .findFirst();
    return entity == null ? null : _mapMerchantRule(entity);
  }

  // ── Operations ─────────────────────────────────────────────────────────────

  @override
  Future<void> applyOperation(
    TaggingOperation operation,
    List<TagAssignment> assignments,
    List<MerchantRuleWrite> ruleWrites,
  ) async {
    _store.runInTransaction(TxMode.write, () {
      _operationBox.put(_mapOperationToEntity(operation));
      _tagAssignmentBox.putMany(
        assignments.map(_mapAssignmentToEntity).toList(growable: false),
      );
      for (final rule in ruleWrites) {
        _upsertMerchantRule(rule);
      }
    });
    for (final assignment in assignments) {
      _assignmentStreams[assignment.transactionId]?.add(assignment);
    }
  }

  @override
  Future<TaggingOperation?> getOperation(String id) async {
    final entity = _operationBox
        .query(TaggingOperationEntity_.operationId.equals(id))
        .build()
        .findFirst();
    return entity == null ? null : _mapOperation(entity);
  }

  @override
  Future<void> restoreOperation(TaggingOperation operation) async {
    final restoredAssignments = <TagAssignment>[];
    final deletedIds = <String>[];

    for (final entry in operation.previousAssignments.entries) {
      final previous = entry.value;
      if (previous != null) {
        restoredAssignments.add(previous);
      } else {
        deletedIds.add(entry.key);
      }
    }

    _store.runInTransaction(TxMode.write, () {
      if (restoredAssignments.isNotEmpty) {
        _tagAssignmentBox.putMany(
          restoredAssignments
              .map(_mapAssignmentToEntity)
              .toList(growable: false),
        );
      }
      if (deletedIds.isNotEmpty) {
        final toRemove = _tagAssignmentBox
            .query(TagAssignmentEntity_.transactionId.oneOf(deletedIds))
            .build()
            .findIds();
        _tagAssignmentBox.removeMany(toRemove);
      }
    });

    for (final entry in operation.previousAssignments.entries) {
      _assignmentStreams[entry.key]?.add(entry.value);
    }
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  Future<void> dispose() async {
    await _catalogChangeController.close();
    for (final ctrl in _assignmentStreams.values) {
      await ctrl.close();
    }
    _assignmentStreams.clear();
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  void _upsertMerchantRule(MerchantRuleWrite rule) {
    final existing = _merchantRuleBox
        .query(
          MerchantTagRuleEntity_.merchantFingerprint
              .equals(rule.fingerprint),
        )
        .build()
        .findFirst();

    if (existing != null) {
      existing.tagId = rule.tagId;
      existing.direction = rule.direction;
      existing.scope = rule.scope;
      existing.createdBy = rule.createdBy;
      existing.evidenceCount += 1;
      existing.confidence = _evidenceConfidence(existing.evidenceCount);
      existing.updatedAt = DateTime.now().toUtc();
      _merchantRuleBox.put(existing);
    } else {
      _merchantRuleBox.put(
        MerchantTagRuleEntity(
          ruleId: '${rule.fingerprint}_${DateTime.now().millisecondsSinceEpoch}',
          merchantFingerprint: rule.fingerprint,
          direction: rule.direction,
          tagId: rule.tagId,
          evidenceCount: 1,
          confidence: 0.78,
          scope: rule.scope,
          createdBy: rule.createdBy,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  double _evidenceConfidence(int count) => switch (count) {
        <= 1 => 0.78,
        2 => 0.90,
        _ => 0.94,
      };

  // ── Mappers ────────────────────────────────────────────────────────────────

  TagAssignment _mapAssignment(TagAssignmentEntity e) => TagAssignment(
        transactionId: e.transactionId,
        tagId: e.tagId,
        source: TagAssignmentSource.values.byName(e.source),
        confidence: e.confidence,
        reasonCode: e.reasonCode,
        ruleOrModelVersion: e.ruleOrModelVersion,
        operationId: e.operationId,
        createdAt: e.createdAt,
        updatedAt: e.updatedAt,
      );

  TagAssignmentEntity _mapAssignmentToEntity(TagAssignment a) {
    final existing = _tagAssignmentBox
        .query(TagAssignmentEntity_.transactionId.equals(a.transactionId))
        .build()
        .findFirst();
    return TagAssignmentEntity(
      objectBoxId: existing?.objectBoxId ?? 0,
      transactionId: a.transactionId,
      tagId: a.tagId,
      source: a.source.name,
      confidence: a.confidence,
      reasonCode: a.reasonCode,
      ruleOrModelVersion: a.ruleOrModelVersion,
      operationId: a.operationId,
      createdAt: a.createdAt,
      updatedAt: a.updatedAt,
    );
  }

  TagDefinition _mapTagDefinition(TagDefinitionEntity e) {
    final aliases = (jsonDecode(e.aliasesJson) as List<dynamic>)
        .map((v) => v.toString())
        .toSet();
    return TagDefinition(
      id: e.tagId,
      schemaVersion: e.schemaVersion,
      displayName: e.displayName,
      classificationId: e.classificationId,
      direction: TagDirection.values.byName(e.direction),
      colorToken: e.colorToken,
      iconToken: e.iconToken,
      source: TagDefinitionSource.values.byName(e.source),
      status: TagDefinitionStatus.values.byName(e.status),
      aliases: aliases,
    );
  }

  TagDefinitionEntity _mapTagDefinitionToEntity(
    TagDefinition tag,
    int objectBoxId,
  ) {
    return TagDefinitionEntity(
      objectBoxId: objectBoxId,
      tagId: tag.id,
      schemaVersion: tag.schemaVersion,
      displayName: tag.displayName,
      normalizedName: tag.displayName.toLowerCase().trim(),
      classificationId: tag.classificationId,
      direction: tag.direction.name,
      colorToken: tag.colorToken,
      iconToken: tag.iconToken,
      source: tag.source.name,
      status: tag.status.name,
      aliasesJson: jsonEncode(tag.aliases.toList()),
    );
  }

  MerchantRuleRecord _mapMerchantRule(MerchantTagRuleEntity e) =>
      MerchantRuleRecord(
        fingerprint: e.merchantFingerprint,
        tagId: e.tagId,
        evidenceCount: e.evidenceCount,
        confidence: e.confidence,
        createdBy: e.createdBy,
      );

  TaggingOperation _mapOperation(TaggingOperationEntity e) {
    final decisionMap = jsonDecode(e.decisionJson) as Map<String, dynamic>;
    final decision = TaggingDecision(
      transactionId: decisionMap['transactionId'] as String,
      tagId: decisionMap['tagId'] as String,
      scope: TaggingScope.values.byName(decisionMap['scope'] as String),
    );
    final prevMap =
        jsonDecode(e.previousAssignmentsJson) as Map<String, dynamic>;
    final previousAssignments = <String, TagAssignment?>{
      for (final entry in prevMap.entries)
        entry.key: entry.value == null
            ? null
            : _decodeAssignment(entry.value as Map<String, dynamic>),
    };
    return TaggingOperation(
      id: e.operationId,
      decision: decision,
      previousAssignments: previousAssignments,
      createdAt: e.createdAt,
      reversibleUntil: e.reversibleUntil,
    );
  }

  TaggingOperationEntity _mapOperationToEntity(TaggingOperation op) {
    final decisionJson = jsonEncode({
      'transactionId': op.decision.transactionId,
      'tagId': op.decision.tagId,
      'scope': op.decision.scope.name,
    });
    final previousJson = jsonEncode({
      for (final entry in op.previousAssignments.entries)
        entry.key: entry.value == null ? null : _encodeAssignment(entry.value!),
    });
    final existing = _operationBox
        .query(TaggingOperationEntity_.operationId.equals(op.id))
        .build()
        .findFirst();
    return TaggingOperationEntity(
      objectBoxId: existing?.objectBoxId ?? 0,
      operationId: op.id,
      decisionJson: decisionJson,
      previousAssignmentsJson: previousJson,
      createdAt: op.createdAt,
      reversibleUntil: op.reversibleUntil,
    );
  }

  Map<String, dynamic> _encodeAssignment(TagAssignment a) => {
        'transactionId': a.transactionId,
        'tagId': a.tagId,
        'source': a.source.name,
        'confidence': a.confidence,
        'reasonCode': a.reasonCode,
        'ruleOrModelVersion': a.ruleOrModelVersion,
        'operationId': a.operationId,
        'createdAt': a.createdAt.toIso8601String(),
        'updatedAt': a.updatedAt.toIso8601String(),
      };

  TagAssignment _decodeAssignment(Map<String, dynamic> m) => TagAssignment(
        transactionId: m['transactionId'] as String,
        tagId: m['tagId'] as String,
        source: TagAssignmentSource.values.byName(m['source'] as String),
        confidence: (m['confidence'] as num).toDouble(),
        reasonCode: m['reasonCode'] as String,
        ruleOrModelVersion: m['ruleOrModelVersion'] as String?,
        operationId: m['operationId'] as String,
        createdAt: DateTime.parse(m['createdAt'] as String),
        updatedAt: DateTime.parse(m['updatedAt'] as String),
      );
}
