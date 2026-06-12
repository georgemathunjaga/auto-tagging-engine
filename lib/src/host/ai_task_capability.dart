// Abstract contract the host app must satisfy for optional remote-AI tagging.
// The host provides this via the 'ai.task.v1' capability key.

enum AiDataClassification {
  public,
  internal,
  financialSensitive,
}

final class AiTaskRequirements {
  final bool structuredJson;

  const AiTaskRequirements({this.structuredJson = false});
}

final class AiTask<T> {
  final String type;
  final AiDataClassification dataClassification;
  final Map<String, Object?> input;
  final AiTaskRequirements requirements;
  final T Function(Object? value) decode;

  const AiTask({
    required this.type,
    required this.dataClassification,
    required this.input,
    required this.requirements,
    required this.decode,
  });
}

sealed class AiTaskResult<T> {}

final class AiTaskSuccess<T> extends AiTaskResult<T> {
  final T value;

  AiTaskSuccess(this.value);
}

final class AiTaskFailure<T> extends AiTaskResult<T> {
  final String reason;

  AiTaskFailure(this.reason);
}

abstract interface class AiTaskCapability {
  Future<AiTaskResult<T>> run<T>(AiTask<T> task);
}
