import 'domain/tagging_models.dart';

final class TagCatalogQuery {
  final TagDirection? direction;
  final bool includeDeprecated;

  const TagCatalogQuery({
    this.direction,
    this.includeDeprecated = false,
  });
}

final class CreateTagRequest {
  final String displayName;
  final String classificationId;
  final TagDirection direction;
  final String colorToken;
  final String iconToken;

  const CreateTagRequest({
    required this.displayName,
    required this.classificationId,
    required this.direction,
    required this.colorToken,
    required this.iconToken,
  });
}

abstract interface class TagCatalogCapability {
  Stream<List<TagDefinition>> watchCatalog(TagCatalogQuery query);
  Future<TagDefinition?> get(String id);
  Future<TagDefinition> createCustomTag(CreateTagRequest request);
  Future<void> deprecateCustomTag(String tagId, {String? replacementTagId});
}

abstract interface class TaggingCapability {
  Stream<TagAssignment?> watchAssignment(String transactionId);
  Future<TagAssignment?> getAssignment(String transactionId);
  Future<TagSuggestionSet> suggest(TaggingRequest request);
  Future<TaggingPreview> preview(TaggingDecision decision);
  Future<TaggingOperation> apply(TaggingDecision decision);
  Future<void> undo(String operationId);
  Future<TaggingRun> autoTag(AutoTagRequest request);
}
