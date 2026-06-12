import 'package:flutter/material.dart';

final class PluginRoute {
  final String name;
  final WidgetBuilder builder;

  const PluginRoute({required this.name, required this.builder});
}

final class ServiceCardContribution {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final Color? iconColor;
  final Color? iconBackgroundColor;
  final bool showNewBadge;
  final String routeName;
  final int sortOrder;

  const ServiceCardContribution({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.iconColor,
    this.iconBackgroundColor,
    this.showNewBadge = false,
    required this.routeName,
    this.sortOrder = 0,
  });
}

final class RouteRegistry {
  final Map<String, PluginRoute> _routes = {};

  void add(String pluginId, PluginRoute route) {
    if (_routes.containsKey(route.name)) {
      throw StateError('Duplicate route ${route.name} from $pluginId.');
    }
    _routes[route.name] = route;
  }

  Map<String, WidgetBuilder> get builders => {
        for (final entry in _routes.entries) entry.key: entry.value.builder,
      };
}

final class ServiceCardRegistry {
  final Map<String, ServiceCardContribution> _cards = {};

  void add(String pluginId, ServiceCardContribution card) {
    if (_cards.containsKey(card.id)) {
      throw StateError('Duplicate service card ${card.id} from $pluginId.');
    }
    _cards[card.id] = card;
  }

  List<ServiceCardContribution> get cards {
    final result = _cards.values.toList(growable: false);
    result.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return result;
  }
}

typedef BackgroundTaskHandler = Future<bool> Function(Map<String, dynamic> input);

final class BackgroundTaskRegistry {
  final Map<String, BackgroundTaskHandler> _handlers = {};

  void add(String taskName, BackgroundTaskHandler handler) {
    if (_handlers.containsKey(taskName)) {
      throw StateError('Duplicate background task $taskName.');
    }
    _handlers[taskName] = handler;
  }

  Future<bool> run(String taskName, Map<String, dynamic> input) async {
    final handler = _handlers[taskName];
    if (handler == null) return false;
    return handler(input);
  }
}
