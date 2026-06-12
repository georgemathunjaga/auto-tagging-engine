final class CapabilityKey<T extends Object> {
  final String name;

  const CapabilityKey(this.name);

  @override
  bool operator ==(Object other) =>
      other is CapabilityKey<Object> && other.name == name;

  @override
  int get hashCode => name.hashCode;
}
