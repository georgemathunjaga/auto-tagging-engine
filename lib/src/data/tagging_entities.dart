// ObjectBox entity classes for the tagging engine.
//
// These classes are annotated with @Entity() so they are picked up by
// objectbox_generator. After adding tagging_engine as a dependency, run:
//
//   dart run build_runner build
//
// in your host app to regenerate its objectbox.g.dart with these entities
// included.

import 'package:objectbox/objectbox.dart';

@Entity()
class TagDefinitionEntity {
  @Id()
  int objectBoxId;

  @Unique()
  String tagId;

  int schemaVersion;
  String displayName;
  String normalizedName;
  String classificationId;

  /// 'income' | 'expense' | 'neutral'
  String direction;
  String colorToken;
  String iconToken;

  /// 'builtIn' | 'system' | 'custom'
  String source;

  /// 'active' | 'deprecated'
  String status;

  /// JSON-encoded list of alias strings.
  String aliasesJson;

  TagDefinitionEntity({
    this.objectBoxId = 0,
    required this.tagId,
    this.schemaVersion = 1,
    required this.displayName,
    required this.normalizedName,
    required this.classificationId,
    required this.direction,
    required this.colorToken,
    required this.iconToken,
    required this.source,
    required this.status,
    required this.aliasesJson,
  });
}

@Entity()
class TagAssignmentEntity {
  @Id()
  int objectBoxId;

  @Unique()
  String transactionId;

  @Index()
  String tagId;

  /// TagAssignmentSource.name
  String source;

  double confidence;
  String reasonCode;
  String? ruleOrModelVersion;
  String operationId;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  TagAssignmentEntity({
    this.objectBoxId = 0,
    required this.transactionId,
    required this.tagId,
    required this.source,
    required this.confidence,
    required this.reasonCode,
    this.ruleOrModelVersion,
    required this.operationId,
    required this.createdAt,
    required this.updatedAt,
  });
}

@Entity()
class MerchantTagRuleEntity {
  @Id()
  int objectBoxId;

  @Unique()
  String ruleId;

  @Index()
  String merchantFingerprint;

  /// 'incoming' | 'outgoing' | 'neutral'
  String direction;

  String tagId;
  int evidenceCount;
  double confidence;

  /// TaggingScope.name or 'user'
  String scope;

  /// 'user' | 'system' | 'auto'
  String createdBy;

  @Property(type: PropertyType.date)
  DateTime updatedAt;

  MerchantTagRuleEntity({
    this.objectBoxId = 0,
    required this.ruleId,
    required this.merchantFingerprint,
    required this.direction,
    required this.tagId,
    required this.evidenceCount,
    required this.confidence,
    required this.scope,
    required this.createdBy,
    required this.updatedAt,
  });
}

@Entity()
class TaggingOperationEntity {
  @Id()
  int objectBoxId;

  @Unique()
  String operationId;

  /// JSON-encoded TaggingDecision.
  String decisionJson;

  /// JSON-encoded Map<transactionId, TagAssignment?>.
  String previousAssignmentsJson;

  @Property(type: PropertyType.date)
  DateTime createdAt;

  @Property(type: PropertyType.date)
  DateTime reversibleUntil;

  TaggingOperationEntity({
    this.objectBoxId = 0,
    required this.operationId,
    required this.decisionJson,
    required this.previousAssignmentsJson,
    required this.createdAt,
    required this.reversibleUntil,
  });
}
