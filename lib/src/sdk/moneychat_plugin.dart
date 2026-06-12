import 'plugin_host.dart';
import 'plugin_manifest.dart';

abstract interface class MoneyChatPlugin {
  PluginManifest get manifest;

  Future<void> register(PluginHost host);
  Future<void> start();
  Future<void> stop();
  Future<void> dispose();
}
