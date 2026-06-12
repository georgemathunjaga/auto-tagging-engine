import 'package:collection/collection.dart';

import '../domain/tagging_models.dart';
import 'candidate_tagger.dart';
import 'tagging_confidence_policy.dart';

final class UnifiedTaggingEngine {
  final List<CandidateTagger> localTaggers;
  final CandidateTagger? remoteTagger;
  final TaggingConfidencePolicy policy;

  const UnifiedTaggingEngine({
    required this.localTaggers,
    required this.remoteTagger,
    required this.policy,
  });

  Future<TagSuggestionSet> suggest(
    TaggingRequest request,
    TaggingContext context,
  ) async {
    final suggestions = <TagSuggestion>[];

    for (final transaction in request.transactions) {
      TaggingCandidate? candidate;

      for (final tagger in localTaggers) {
        candidate = await tagger.candidate(transaction, context);
        if (candidate != null) break;
      }

      if (candidate == null &&
          request.allowRemoteAi &&
          remoteTagger != null) {
        candidate = await remoteTagger!.candidate(transaction, context);
      }

      if (candidate == null) {
        suggestions.add(
          TagSuggestion(
            transaction: transaction,
            candidate: null,
            action: TaggingAction.suppress,
          ),
        );
        continue;
      }

      final tag =
          context.catalog.firstWhereOrNull((t) => t.id == candidate!.tagId);
      suggestions.add(
        TagSuggestion(
          transaction: transaction,
          candidate: candidate,
          action: tag == null
              ? TaggingAction.suppress
              : policy.decide(transaction, tag, candidate),
        ),
      );
    }

    return TagSuggestionSet(
      suggestions: suggestions,
      generatedAt: DateTime.now().toUtc(),
    );
  }
}
