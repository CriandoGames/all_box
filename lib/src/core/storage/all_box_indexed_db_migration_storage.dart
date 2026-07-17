import 'dart:convert';

import 'all_box_indexed_db_storage.dart';
import 'all_box_storage.dart';
import 'all_box_storage_exception.dart';
import 'all_box_web_storage.dart';

/// Internal migration wrapper for the beta IndexedDB Web backend.
///
/// This is selected only when `AllBox.init()` receives
/// `experimentalIndexedDbBackend: true`. It proves the localStorage ->
/// IndexedDB compatibility path before changing the default Web backend.
class AllBoxIndexedDbMigrationStorage implements AllBoxStorage {
  AllBoxIndexedDbMigrationStorage({
    required this.container,
    required AllBoxIndexedDbDriver indexedDb,
    required AllBoxBrowserStorage legacyStorage,
  })  : _indexedDb = indexedDb,
        _legacyStorage = legacyStorage;

  final String container;
  final AllBoxIndexedDbDriver _indexedDb;
  final AllBoxBrowserStorage _legacyStorage;
  Map<String, dynamic> _baseSnapshot = <String, dynamic>{};

  String get _legacyKey => 'all_box::$container';

  @override
  Future<bool> hasPersistedData() async {
    try {
      if (await _indexedDb.contains(container)) return true;
    } on Object {
      return _hasLegacyDataOrThrow();
    }
    return _hasLegacyDataOrThrow();
  }

  @override
  Future<Map<String, dynamic>> load() async {
    final String? indexedRaw;
    try {
      indexedRaw = await _indexedDb.read(container);
    } on Object {
      return _loadLegacy();
    }

    if (indexedRaw != null) {
      final loaded = _decodeJsonMapOrEmpty(indexedRaw);
      _baseSnapshot = _copyJsonMap(loaded);
      return _copyJsonMap(loaded);
    }

    final legacyRaw = _readLegacyRaw();
    if (legacyRaw == null) {
      _baseSnapshot = <String, dynamic>{};
      return <String, dynamic>{};
    }

    final loaded = _decodeJsonMapOrEmpty(legacyRaw);
    _baseSnapshot = _copyJsonMap(loaded);
    if (loaded.isEmpty && legacyRaw.trim() != '{}') return loaded;

    try {
      await _indexedDb.update(container, (currentJsonText) {
        return currentJsonText ?? legacyRaw;
      });
      _legacyStorage.removeItem(_legacyKey);
    } on Object {
      // Keep localStorage intact until IndexedDB has definitely accepted the
      // migrated value. Loading still succeeds from the legacy copy.
    }

    return loaded;
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
        'IndexedDB migration storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _indexedDb.update(container, (currentJsonText) {
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
      _legacyStorage.removeItem(_legacyKey);
      // Keep the local base as this instance's own persisted view, not the
      // merged global snapshot. Otherwise remote keys preserved from another
      // tab would look like local deletions on the next save.
      _baseSnapshot = _copyJsonMap(localSnapshot);
    } on Object catch (indexedError) {
      final jsonText = jsonEncode(localSnapshot);
      try {
        _legacyStorage.setItem(_legacyKey, jsonText);
      } on Object catch (legacyError, legacyStackTrace) {
        throw AllBoxStorageException(
          'AllBox("$container"): failed to write to IndexedDB storage and '
          'the localStorage fallback also failed.',
          cause: <Object>[indexedError, legacyError],
          stackTrace: legacyStackTrace,
        );
      }
      _baseSnapshot = _copyJsonMap(localSnapshot);
      return;
    }
  }

  @override
  Future<void> delete() async {
    Object? indexedError;
    StackTrace? indexedStackTrace;
    try {
      await _indexedDb.delete(container);
    } on Object catch (error, stackTrace) {
      indexedError = error;
      indexedStackTrace = stackTrace;
    }

    try {
      _legacyStorage.removeItem(_legacyKey);
    } on Object catch (legacyError, legacyStackTrace) {
      throw AllBoxStorageException(
        indexedError == null
            ? 'AllBox("$container"): failed to delete legacy localStorage data.'
            : 'AllBox("$container"): failed to delete IndexedDB data and '
                'legacy localStorage data.',
        cause: indexedError == null
            ? legacyError
            : <Object>[indexedError, legacyError],
        stackTrace: legacyStackTrace,
      );
    }

    if (indexedError != null) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to delete IndexedDB data. Legacy '
        'localStorage data was removed, but IndexedDB may still contain data.',
        cause: indexedError,
        stackTrace: indexedStackTrace,
      );
    }
  }

  @override
  Future<void> close() async {
    try {
      await _indexedDb.close();
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to close IndexedDB migration storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  bool _hasLegacyDataOrThrow() {
    try {
      return _legacyStorage.getItem(_legacyKey) != null;
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to check legacy localStorage data.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Map<String, dynamic> _loadLegacy() {
    final raw = _readLegacyRaw();
    if (raw == null) {
      _baseSnapshot = <String, dynamic>{};
      return <String, dynamic>{};
    }
    final loaded = _decodeJsonMapOrEmpty(raw);
    _baseSnapshot = _copyJsonMap(loaded);
    return _copyJsonMap(loaded);
  }

  String? _readLegacyRaw() {
    try {
      return _legacyStorage.getItem(_legacyKey);
    } on Object {
      return null;
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
