import 'dart:convert';

import 'all_box_storage.dart';
import 'all_box_storage_exception.dart';

/// Minimal asynchronous key/value driver used by [AllBoxIndexedDbStorage].
///
/// This interface deliberately stores a single JSON string per container.
/// The IndexedDB-specific implementation lives in a Web-only file; keeping
/// this wrapper free of `dart:js_interop` lets the JSON/error semantics be
/// tested on the VM with a fake driver.
abstract interface class AllBoxIndexedDbDriver {
  Future<bool> contains(String container);

  Future<String?> read(String container);

  Future<void> write(String container, String jsonText);

  Future<String> update(
    String container,
    String Function(String? currentJsonText) merge,
  );

  Future<void> delete(String container);

  Future<void> close();
}

/// Internal, not-default IndexedDB-backed storage.
///
/// `AllBox.init()` still resolves to `window.localStorage` by default on
/// Web. This class keeps the IndexedDB persistence contract isolated while
/// the beta migration path is validated before any default-backend switch.
class AllBoxIndexedDbStorage implements AllBoxStorage {
  AllBoxIndexedDbStorage({
    required this.container,
    required AllBoxIndexedDbDriver driver,
  }) : _driver = driver;

  final String container;
  final AllBoxIndexedDbDriver _driver;
  Map<String, dynamic> _baseSnapshot = <String, dynamic>{};

  @override
  Future<bool> hasPersistedData() async {
    try {
      return await _driver.contains(container);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to check for existing IndexedDB data.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> load() async {
    final String? raw;
    try {
      raw = await _driver.read(container);
    } on Object {
      // Match the AllBoxStorage contract: load must not crash the caller.
      _baseSnapshot = <String, dynamic>{};
      return <String, dynamic>{};
    }

    if (raw == null) {
      _baseSnapshot = <String, dynamic>{};
      return <String, dynamic>{};
    }

    final decoded = _decodeJsonMapOrEmpty(raw);
    _baseSnapshot = _copyJsonMap(decoded);
    return _copyJsonMap(decoded);
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    final Map<String, dynamic> localSnapshot;
    try {
      localSnapshot = _normalizeJsonMap(snapshot);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to encode snapshot to JSON for '
        'IndexedDB storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _driver.update(container, (currentJsonText) {
        final currentSnapshot = currentJsonText == null
            ? <String, dynamic>{}
            : _decodeJsonMapOrEmpty(currentJsonText);
        final merged = _mergeSnapshotDelta(
          baseSnapshot: _baseSnapshot,
          localSnapshot: localSnapshot,
          currentSnapshot: currentSnapshot,
        );
        return jsonEncode(merged);
      });
      // Keep the local base as this instance's own persisted view, not the
      // merged global snapshot. Otherwise remote keys preserved from another
      // tab would look like local deletions on the next save.
      _baseSnapshot = _copyJsonMap(localSnapshot);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to write to IndexedDB storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> delete() async {
    try {
      await _driver.delete(container);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to delete IndexedDB storage data.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close() async {
    try {
      await _driver.close();
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to close IndexedDB storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }
}

Map<String, dynamic> _decodeJsonMapOrEmpty(String raw) {
  try {
    final dynamic decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return _copyJsonMap(decoded);
    if (decoded is Map<dynamic, dynamic>) {
      return _copyJsonMap(Map<String, dynamic>.from(decoded));
    }
    return <String, dynamic>{};
  } on FormatException {
    return <String, dynamic>{};
  }
}

Map<String, dynamic> _normalizeJsonMap(Map<String, dynamic> snapshot) {
  final dynamic decoded = jsonDecode(jsonEncode(snapshot));
  if (decoded is Map<String, dynamic>) return _copyJsonMap(decoded);
  if (decoded is Map<dynamic, dynamic>) {
    return _copyJsonMap(Map<String, dynamic>.from(decoded));
  }
  return <String, dynamic>{};
}

Map<String, dynamic> _copyJsonMap(Map<String, dynamic> source) {
  return <String, dynamic>{
    for (final entry in source.entries) entry.key: _copyJsonValue(entry.value),
  };
}

dynamic _copyJsonValue(dynamic value) {
  if (value is Map<String, dynamic>) return _copyJsonMap(value);
  if (value is Map<dynamic, dynamic>) {
    return _copyJsonMap(Map<String, dynamic>.from(value));
  }
  if (value is List) return value.map(_copyJsonValue).toList();
  return value;
}

Map<String, dynamic> _mergeSnapshotDelta({
  required Map<String, dynamic> baseSnapshot,
  required Map<String, dynamic> localSnapshot,
  required Map<String, dynamic> currentSnapshot,
}) {
  final merged = _copyJsonMap(currentSnapshot);

  for (final key in baseSnapshot.keys) {
    if (!localSnapshot.containsKey(key)) {
      merged.remove(key);
    }
  }

  for (final entry in localSnapshot.entries) {
    final key = entry.key;
    if (!baseSnapshot.containsKey(key) ||
        !_jsonEquals(baseSnapshot[key], entry.value)) {
      merged[key] = _copyJsonValue(entry.value);
    }
  }

  return merged;
}

bool _jsonEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  return jsonEncode(a) == jsonEncode(b);
}
