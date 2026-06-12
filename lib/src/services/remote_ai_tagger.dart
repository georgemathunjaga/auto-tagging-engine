import '../domain/tagging_models.dart';
import '../host/ai_task_capability.dart';
import '../tagging_config.dart';
import 'candidate_tagger.dart';

final class RemoteAiTagger implements CandidateTagger {
  final AiTaskCapability _ai;
  final RemoteAiConfig _config;

  const RemoteAiTagger({
    required AiTaskCapability ai,
    RemoteAiConfig config = const RemoteAiConfig(),
  })  : _ai = ai,
        _config = config;

  @override
  String get id => 'remote_ai.v1';

  @override
  Future<TaggingCandidate?> candidate(
    TaggingTransaction transaction,
    TaggingContext context,
  ) async {
    final input = _buildInput(transaction, context);

    final response = await _ai.run<Map<String, dynamic>>(
      AiTask(
        type: 'tagging.suggest.v1',
        dataClassification: AiDataClassification.financialSensitive,
        input: input,
        requirements: const AiTaskRequirements(structuredJson: true),
        decode: (value) {
          if (value is! Map<String, dynamic>) {
            throw const FormatException('Expected JSON object.');
          }
          return value;
        },
      ),
    );

    if (response is! AiTaskSuccess<Map<String, dynamic>>) return null;

    final tagId = response.value['tag_id']?.toString() ?? '';
    if (tagId.isEmpty) return null;
    if (!context.catalog.any((t) => t.id == tagId)) return null;

    final confidence =
        (response.value['confidence'] as num?)?.toDouble() ?? 0.0;
    return TaggingCandidate(
      tagId: tagId,
      confidence: confidence.clamp(0.0, 1.0),
      source: TagAssignmentSource.remoteAi,
      reasonCode:
          response.value['reason_code']?.toString() ?? 'remote_ai',
      version: id,
    );
  }

  Map<String, Object?> _buildInput(
    TaggingTransaction transaction,
    TaggingContext context,
  ) {
    final fields = _config.allowedFields;
    return {
      'transaction': {
        if (fields.contains(RemoteAiField.merchant))
          'merchant': transaction.merchant,
        if (fields.contains(RemoteAiField.direction))
          'direction': transaction.direction,
        if (fields.contains(RemoteAiField.kind)) 'kind': transaction.kind,
        if (fields.contains(RemoteAiField.amountMinor))
          'amount_minor': transaction.amountMinor,
        if (fields.contains(RemoteAiField.currency))
          'currency': transaction.currency,
      },
      'allowed_tags': [
        for (final tag in context.catalog)
          {
            'id': tag.id,
            'name': tag.displayName,
            'direction': tag.direction.name,
          },
      ],
    };
  }
}
