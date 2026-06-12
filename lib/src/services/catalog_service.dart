import '../data/tagging_repository.dart';
import '../domain/tagging_models.dart';
import '../tagging_api.dart';

final class PluginTagCatalogService implements TagCatalogCapability {
  final TaggingRepository _repository;

  const PluginTagCatalogService(this._repository);

  @override
  Stream<List<TagDefinition>> watchCatalog(TagCatalogQuery query) async* {
    yield await _repository.catalog(query);
    await for (final _ in _repository.watchCatalogChanges()) {
      yield await _repository.catalog(query);
    }
  }

  @override
  Future<TagDefinition?> get(String id) => _repository.getTag(id);

  @override
  Future<TagDefinition> createCustomTag(CreateTagRequest request) async {
    final normalized = request.displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    if (normalized.isEmpty) throw ArgumentError('Tag name is empty.');

    final id = 'custom.$normalized';
    final existing = await _repository.getTag(id);
    if (existing != null && existing.status == TagDefinitionStatus.active) {
      throw StateError('A tag with id "$id" already exists.');
    }

    final tag = TagDefinition(
      id: id,
      displayName: request.displayName.trim(),
      classificationId: request.classificationId,
      direction: request.direction,
      colorToken: request.colorToken,
      iconToken: request.iconToken,
      source: TagDefinitionSource.custom,
    );
    await _repository.saveTag(tag);
    return tag;
  }

  @override
  Future<void> deprecateCustomTag(
    String tagId, {
    String? replacementTagId,
  }) async {
    final existing = await _repository.getTag(tagId);
    if (existing == null || existing.source != TagDefinitionSource.custom) {
      throw StateError('Only custom tags can be deprecated here.');
    }
    await _repository.saveTag(
      TagDefinition(
        id: existing.id,
        schemaVersion: existing.schemaVersion,
        displayName: existing.displayName,
        classificationId: existing.classificationId,
        direction: existing.direction,
        colorToken: existing.colorToken,
        iconToken: existing.iconToken,
        source: existing.source,
        status: TagDefinitionStatus.deprecated,
        aliases: existing.aliases,
      ),
    );
  }
}
