enum PluginPermission {
  camera,
  photos,
  readSms,
  receiveSms,
  network,
  notifications,
  backgroundTasks,
  secureStorage,
}

final class PluginManifest {
  final String id;
  final String version;
  final Set<String> provides;
  final Set<String> requires;
  final Set<String> optional;
  final Set<PluginPermission> permissions;

  const PluginManifest({
    required this.id,
    required this.version,
    this.provides = const {},
    this.requires = const {},
    this.optional = const {},
    this.permissions = const {},
  });
}
