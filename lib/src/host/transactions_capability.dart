// Abstract contract the host app must satisfy for the tagging engine to read
// transaction data. The host provides this via the 'transactions.query.v1'
// capability key.

enum TransactionDirection { incoming, outgoing }

enum TransactionKind {
  payment,
  transfer,
  withdrawal,
  deposit,
  reversal,
  other,
}

final class TransactionCounterparty {
  final String displayName;
  final String? protectedPhoneSuffix;

  const TransactionCounterparty({
    required this.displayName,
    this.protectedPhoneSuffix,
  });
}

abstract final class TransactionRecord {
  String get id;
  String get sourceId;
  String get sourceTransactionId;
  TransactionCounterparty get counterparty;
  TransactionDirection get direction;
  TransactionKind get kind;
  int get amountMinor;
  String get currency;
  DateTime get occurredAt;

  /// Stable fingerprint produced by the transactions plugin (or computed by the
  /// host from merchant + direction + source). Used for merchant-rule lookups.
  String get merchantFingerprint;
}

final class TransactionQuery {
  final String? merchantFingerprint;
  final DateTime? from;
  final DateTime? to;
  final int limit;

  const TransactionQuery({
    this.merchantFingerprint,
    this.from,
    this.to,
    this.limit = 100,
  });
}

final class TransactionPage {
  final List<TransactionRecord> items;
  final bool hasMore;

  const TransactionPage({required this.items, required this.hasMore});
}

abstract interface class TransactionsQueryCapability {
  Future<TransactionRecord?> get(String transactionId);
  Future<TransactionPage> page(TransactionQuery query);
}
