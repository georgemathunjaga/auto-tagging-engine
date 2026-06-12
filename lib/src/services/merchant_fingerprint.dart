import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/tagging_models.dart';

final class MerchantFingerprint {
  static final _nonAlphaNumeric = RegExp(r'[^a-z0-9]+');

  const MerchantFingerprint();

  String forTransaction(TaggingTransaction transaction) {
    final merchant = normalize(transaction.merchant);
    final phone = transaction.protectedPhoneSuffix?.trim() ?? '';
    final material = [
      transaction.sourceId.toLowerCase(),
      merchant,
      transaction.direction.toLowerCase(),
      transaction.kind.toLowerCase(),
      phone,
    ].join('|');
    return sha256.convert(utf8.encode(material)).toString();
  }

  String normalize(String value) => value
      .toLowerCase()
      .replaceAll(_nonAlphaNumeric, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
