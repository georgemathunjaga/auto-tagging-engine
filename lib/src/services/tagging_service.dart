import 'dart:math';

import '../data/tagging_repository.dart';
import '../domain/tagging_models.dart';
import '../host/transactions_capability.dart';
import '../tagging_api.dart';
import '../tagging_config.dart';
import 'candidate_tagger.dart';
import 'merchant_fingerprint.dart';
import 'unified_tagging_engine.dart';

// Maps a host TransactionRecord to the engine's agnostic TaggingTransaction.
extension _TransactionMapper on TransactionRecord {
  TaggingTransaction toTaggingTransaction() => TaggingTransaction(
        id: id,
        sourceId: sourceId,
        sourceTransactionId: sourceTransactionId,
        merchant: counterparty.displayName,
        protectedPhoneSuffix: counterparty.protectedPhoneSuffix,
        direction: direction.name,
        kind: kind.name,
        amountMinor: amountMinor,
        currency: currency,
        occurredAt: occurredAt,
      );
}

final class PluginTaggingService implements TaggingCapability {
  final TransactionsQueryCapability _transactions;
  final TaggingRepository _repository;
  final UnifiedTaggingEngine _engine;
  final MerchantFingerprint _fingerprint;
  final Future<TaggingContext> Function() _contextBuilder;
  final AutoTagRunConfig _autoTagConfig;
  final TaggingAuditConfig _auditConfig;
  final DateTime Function() _now;

  PluginTaggingService({
    required TransactionsQueryCapability transactions,
    required TaggingRepository repository,
    required UnifiedTaggingEngine engine,
    required MerchantFingerprint fingerprint,
    required Future<TaggingContext> Function() contextBuilder,
    AutoTagRunConfig config = const AutoTagRunConfig(),
    TaggingAuditConfig auditConfig = const TaggingAuditConfig(),
    DateTime Function()? now,
  })  : _transactions = transactions,
        _repository = repository,
        _engine = engine,
        _fingerprint = fingerprint,
        _contextBuilder = contextBuilder,
        _autoTagConfig = config,
        _auditConfig = auditConfig,
        _now = now ?? DateTime.now;

  @override
  Stream<TagAssignment?> watchAssignment(String transactionId) =>
      _repository.watchAssignment(transactionId);

  @override
  Future<TagAssignment?> getAssignment(String transactionId) =>
      _repository.getAssignment(transactionId);

  @override
  Future<TagSuggestionSet> suggest(TaggingRequest request) async {
    return _engine.suggest(request, await _contextBuilder());
  }

  @override
  Future<TaggingPreview> preview(TaggingDecision decision) async {
    final source = await _transactions.get(decision.transactionId);
    if (source == null) throw StateError('Transaction not found.');

    final matches = switch (decision.scope) {
      TaggingScope.transactionOnly => [source],
      TaggingScope.matchingUntagged ||
      TaggingScope.allMatching ||
      TaggingScope.futureMatching =>
        (await _transactions.page(
          TransactionQuery(
            merchantFingerprint: source.merchantFingerprint,
            limit: 500,
          ),
        )).items,
    };

    final assignments = await _repository.getAssignments(
      matches.map((tx) => tx.id),
    );
    final assignedIds =
        assignments.map((a) => a.transactionId).toSet();

    final affected = decision.scope == TaggingScope.matchingUntagged
        ? matches.where((tx) => !assignedIds.contains(tx.id)).toList()
        : List<TransactionRecord>.from(matches);

    affected.sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return TaggingPreview(
      decision: decision,
      affectedTransactionIds:
          affected.map((tx) => tx.id).toList(growable: false),
      alreadyTaggedCount:
          affected.where((tx) => assignedIds.contains(tx.id)).length,
      earliest: affected.isEmpty ? null : affected.first.occurredAt,
      latest: affected.isEmpty ? null : affected.last.occurredAt,
    );
  }

  @override
  Future<TaggingOperation> apply(TaggingDecision decision) async {
    final previewResult = await preview(decision);
    final previous = <String, TagAssignment?>{};
    for (final id in previewResult.affectedTransactionIds) {
      previous[id] = await _repository.getAssignment(id);
    }

    final timestamp = _now().toUtc();
    final operation = TaggingOperation(
      id: 'tagop_${timestamp.microsecondsSinceEpoch}_'
          '${Random.secure().nextInt(1 << 32)}',
      decision: decision,
      previousAssignments: previous,
      createdAt: timestamp,
      reversibleUntil: timestamp.add(_auditConfig.undoWindow),
    );

    final assignments = [
      for (final id in previewResult.affectedTransactionIds)
        TagAssignment(
          transactionId: id,
          tagId: decision.tagId,
          source: decision.scope == TaggingScope.transactionOnly
              ? TagAssignmentSource.manual
              : TagAssignmentSource.propagation,
          confidence: 1.0,
          reasonCode: 'user_decision',
          operationId: operation.id,
          createdAt: previous[id]?.createdAt ?? timestamp,
          updatedAt: timestamp,
        ),
    ];

    final source = await _transactions.get(decision.transactionId);
    final ruleWrites = <MerchantRuleWrite>[
      if (source != null && decision.scope == TaggingScope.futureMatching)
        MerchantRuleWrite(
          fingerprint: source.merchantFingerprint,
          direction: source.direction.name,
          tagId: decision.tagId,
          scope: decision.scope.name,
          createdBy: 'user',
        ),
    ];

    await _repository.applyOperation(operation, assignments, ruleWrites);
    return operation;
  }

  @override
  Future<void> undo(String operationId) async {
    final operation = await _repository.getOperation(operationId);
    if (operation == null) throw StateError('Tagging operation not found.');
    if (_now().toUtc().isAfter(operation.reversibleUntil)) {
      throw StateError('The undo period has expired.');
    }
    await _repository.restoreOperation(operation);
  }

  @override
  Future<TaggingRun> autoTag(AutoTagRequest request) async {
    final records = <TaggingTransaction>[];
    for (final id in request.transactionIds) {
      final tx = await _transactions.get(id);
      if (tx == null || await _repository.getAssignment(id) != null) continue;
      records.add(tx.toTaggingTransaction());
    }

    final suggestionSet = await suggest(
      TaggingRequest(
        transactions: records,
        allowRemoteAi: request.allowRemoteAi,
      ),
    );

    var applied = 0;
    var suggested = 0;
    var suppressed = 0;

    final limit = request.maximumAutoApply > 0
        ? request.maximumAutoApply
        : _autoTagConfig.maximumAutoApply;

    for (final suggestion in suggestionSet.suggestions) {
      switch (suggestion.action) {
        case TaggingAction.autoApply:
          if (applied >= limit) {
            suggested++;
            continue;
          }
          await apply(
            TaggingDecision(
              transactionId: suggestion.transaction.id,
              tagId: suggestion.candidate!.tagId,
              scope: TaggingScope.transactionOnly,
            ),
          );
          applied++;
        case TaggingAction.suggest:
          suggested++;
        case TaggingAction.suppress:
          suppressed++;
      }
    }

    return TaggingRun(
      considered: suggestionSet.suggestions.length,
      applied: applied,
      suggested: suggested,
      suppressed: suppressed,
    );
  }
}
