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

  Future<void> delete(String container);

  Future<void> close();
}

/// Internal, not-yet-default IndexedDB-backed storage.
///
/// Stage 1 keeps this storage inactive: `AllBox.init()` still resolves to the
/// existing `window.localStorage` backend on Web. This class exists so the
/// IndexedDB persistence contract can be tested before it becomes a default
/// backend.
class AllBoxIndexedDbStorage implements AllBoxStorage {
  AllBoxIndexedDbStorage({
    required this.container,
    required AllBoxIndexedDbDriver driver,
  }) : _driver = driver;

  final String container;
  final AllBoxIndexedDbDriver _driver;

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
      return <String, dynamic>{};
    }

    if (raw == null) return <String, dynamic>{};

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
        'IndexedDB storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      await _driver.write(container, jsonText);
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
