import 'dart:async';

abstract interface class PluginEvent {
  String get name;
  int get schemaVersion;
  DateTime get occurredAt;
}

final class PluginEventBus {
  final StreamController<PluginEvent> _controller =
      StreamController<PluginEvent>.broadcast(sync: true);

  Stream<T> on<T extends PluginEvent>() => _controller.stream.whereType<T>();

  void publish(PluginEvent event) {
    if (_controller.isClosed) return;
    _controller.add(event);
  }

  Future<void> close() => _controller.close();
}
