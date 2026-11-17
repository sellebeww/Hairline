// Copyright (c) 2026 Vassel Goleyu. MIT License.

/// Raised after a scope finished when releasing resources failed. Every resource was
/// still released; [errors] are the failures in release order.
final class ResourceDisposeException implements Exception {
  const ResourceDisposeException(this.errors);
  final List<Object> errors;

  @override
  String toString() => 'ResourceDisposeException(${errors.length} failures: ${errors.first})';
}

/// Owns native or otherwise scarce resources for the duration of one piece of work.
///
/// Adapters (OpenCV `Mat`, vectors, detectors) register each resource right after
/// creating it with [add]; [run] releases all of them in reverse order when the body
/// returns OR throws, and a failing release never prevents the others from running.
/// This is the single disposal pattern of the native adapters (CLAUDE.md rule 10),
/// kept in the pure core so that it can be tested without the native library.
final class ResourceScope {
  ResourceScope._();

  final List<void Function()> _release = [];
  bool _closed = false;

  /// Registers [resource] for release with [dispose] and returns it.
  T add<T>(T resource, void Function(T resource) dispose) {
    if (_closed) throw StateError('ResourceScope already closed');
    _release.add(() => dispose(resource));
    return resource;
  }

  /// Runs [body], then releases everything registered. If [body] throws, its error
  /// wins; otherwise a failed release surfaces as [ResourceDisposeException].
  static R run<R>(R Function(ResourceScope scope) body) {
    final scope = ResourceScope._();
    final R result;
    try {
      result = body(scope);
    } finally {
      scope._closeSilently();
    }
    if (scope._failures.isNotEmpty) throw ResourceDisposeException(scope._failures);
    return result;
  }

  final List<Object> _failures = [];

  void _closeSilently() {
    _closed = true;
    for (final release in _release.reversed) {
      try {
        release();
      } catch (e) {
        _failures.add(e);
      }
    }
    _release.clear();
  }
}
