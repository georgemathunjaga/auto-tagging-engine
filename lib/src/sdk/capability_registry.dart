import 'capability_key.dart';

final class CapabilityRegistry {
  final Map<String, Object> _values = {};
  final Map<String, String> _owners = {};

  void provide<T extends Object>({
    required String pluginId,
    required CapabilityKey<T> key,
    required T value,
  }) {
    final owner = _owners[key.name];
    if (owner != null && owner != pluginId) {
      throw StateError(
        'Capability ${key.name} is already provided by $owner.',
      );
    }
    _owners[key.name] = pluginId;
    _values[key.name] = value;
  }

  T require<T extends Object>(CapabilityKey<T> key) {
    final value = _values[key.name];
    if (value == null) {
      throw StateError('Required capability ${key.name} is unavailable.');
    }
    if (value is! T) {
      throw StateError(
        'Capability ${key.name} has type ${value.runtimeType}, expected $T.',
      );
    }
    return value;
  }

  T? optional<T extends Object>(CapabilityKey<T> key) {
    final value = _values[key.name];
    return value is T ? value : null;
  }

  bool contains(String name) => _values.containsKey(name);

  void removeOwnedBy(String pluginId) {
    final names = _owners.entries
        .where((e) => e.value == pluginId)
        .map((e) => e.key)
        .toList(growable: false);
    for (final name in names) {
      _owners.remove(name);
      _values.remove(name);
    }
  }
}
