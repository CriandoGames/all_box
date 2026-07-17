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

    if (indexedRaw != null) return _decodeOrEmpty(indexedRaw);

    final legacyRaw = _readLegacyRaw();
    if (legacyRaw == null) return <String, dynamic>{};

    final loaded = _decodeOrEmpty(legacyRaw);
    if (loaded.isEmpty && legacyRaw.trim() != '{}') return loaded;

    try {
      await _indexedDb.write(container, legacyRaw);
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
    final String jsonText;
    try {
      jsonText = jsonEncode(snapshot);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to encode snapshot to JSON for '
        'IndexedDB migration storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _indexedDb.write(container, jsonText);
      _legacyStorage.removeItem(_legacyKey);
    } on Object catch (indexedError) {
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
    if (raw == null) return <String, dynamic>{};
    return _decodeOrEmpty(raw);
  }

  String? _readLegacyRaw() {
    try {
      return _legacyStorage.getItem(_legacyKey);
    } on Object {
      return null;
    }
  }

  Map<String, dynamic> _decodeOrEmpty(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map<dynamic, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }
}
