abstract interface class SecureSecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

abstract interface class NamespacedKeyValueStore {
  String? getString(String key);
  int? getInt(String key);
  bool? getBool(String key);
  List<String>? getStringList(String key);

  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> setBool(String key, bool value);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);
}

abstract interface class ConsentService {
  Future<bool> isGranted(String consentId, int version);
  Future<bool> request(String consentId, int version);
  Future<void> revoke(String consentId);
}

abstract interface class SubscriptionCapabilities {
  bool has(String capability);
  Stream<Set<String>> watch();
}

abstract interface class TelemetrySink {
  void count(String name, {Map<String, String> dimensions = const {}});
  void timing(
    String name,
    Duration duration, {
    Map<String, String> dimensions = const {},
  });
  void error(
    String name,
    Object error, {
    StackTrace? stackTrace,
    Map<String, String> dimensions = const {},
  });
}
