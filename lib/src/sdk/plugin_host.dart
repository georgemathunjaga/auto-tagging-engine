import 'capability_registry.dart';
import 'host_services.dart';
import 'plugin_event.dart';
import 'registries.dart';

final class PluginHost {
  final CapabilityRegistry capabilities;
  final PluginEventBus events;
  final RouteRegistry routes;
  final ServiceCardRegistry serviceCards;
  final BackgroundTaskRegistry backgroundTasks;
  final SecureSecretStore secrets;
  final NamespacedKeyValueStore preferences;
  final ConsentService consent;
  final SubscriptionCapabilities subscriptions;
  final TelemetrySink telemetry;

  const PluginHost({
    required this.capabilities,
    required this.events,
    required this.routes,
    required this.serviceCards,
    required this.backgroundTasks,
    required this.secrets,
    required this.preferences,
    required this.consent,
    required this.subscriptions,
    required this.telemetry,
  });
}
