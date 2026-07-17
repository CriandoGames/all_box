import 'dart:async';
import 'dart:js_interop';

import '../all_box_indexed_db_storage.dart';

const String _storeName = 'containers';
const int _schemaVersion = 1;

@JS('indexedDB')
external _IDBFactory? get _indexedDb;

extension type _IDBFactory._(JSObject _) implements JSObject {
  external _IDBOpenDBRequest open(JSString name, JSNumber version);
  external _IDBOpenDBRequest deleteDatabase(JSString name);
}

extension type _DOMStringList._(JSObject _) implements JSObject {
  external bool contains(JSString value);
}

extension type _DOMException._(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get message;
}

extension type _IDBOpenDBRequest._(JSObject _) implements JSObject {
  external set onsuccess(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external set onblocked(JSFunction? callback);
  external set onupgradeneeded(JSFunction? callback);
  external _IDBDatabase get result;
  external _DOMException? get error;
}

extension type _IDBRequest._(JSObject _) implements JSObject {
  external set onsuccess(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external JSAny? get result;
  external _DOMException? get error;
}

extension type _IDBDatabase._(JSObject _) implements JSObject {
  external JSNumber get version;
  external _DOMStringList get objectStoreNames;
  external _IDBObjectStore createObjectStore(JSString name);
  external _IDBTransaction transaction(JSString storeName, JSString mode);
  external void close();
  external set onversionchange(JSFunction? callback);
}

extension type _IDBTransaction._(JSObject _) implements JSObject {
  external _IDBObjectStore objectStore(JSString name);
  external set oncomplete(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external set onabort(JSFunction? callback);
  external _DOMException? get error;
}

extension type _IDBObjectStore._(JSObject _) implements JSObject {
  external _IDBRequest get(JSString key);
  external _IDBRequest put(JSString value, JSString key);
  external _IDBRequest delete(JSString key);
  external _IDBRequest count(JSString key);
}

/// Web-only IndexedDB driver for [AllBoxIndexedDbStorage].
///
/// The current `window.localStorage` default stays unchanged while this
/// driver is exercised through the explicit beta IndexedDB opt-in and
/// dedicated browser tests.
class AllBoxBrowserIndexedDbDriver implements AllBoxIndexedDbDriver {
  AllBoxBrowserIndexedDbDriver({this.databaseName = 'all_box'});

  static const int schemaVersionForTesting = _schemaVersion;
  static const String storeNameForTesting = _storeName;

  final String databaseName;

  _IDBDatabase? _db;
  Future<_IDBDatabase>? _opening;

  @override
  Future<bool> contains(String container) async {
    return _withStore('readonly', (store) async {
      final result = await _waitForRequest(store.count(container.toJS));
      final count = result.dartify();
      return count is num && count > 0;
    });
  }

  @override
  Future<String?> read(String container) async {
    return _withStore('readonly', (store) async {
      final result = await _waitForRequest(store.get(container.toJS));
      final value = result.dartify();
      return value is String ? value : null;
    });
  }

  @override
  Future<void> write(String container, String jsonText) async {
    await _withStore('readwrite', (store) async {
      await _waitForRequest(store.put(jsonText.toJS, container.toJS));
    });
  }

  @override
  Future<void> delete(String container) async {
    await _withStore('readwrite', (store) async {
      await _waitForRequest(store.delete(container.toJS));
    });
  }

  @override
  Future<void> close() async {
    _opening = null;
    final db = _db;
    if (db == null) return;
    _db = null;
    db.close();
  }

  static Future<void> deleteDatabaseForTesting(String databaseName) async {
    final factory = _indexedDb;
    if (factory == null) return;
    final request = factory.deleteDatabase(databaseName.toJS);
    await _waitForDeleteDatabaseRequest(request);
  }

  Future<T> _withStore<T>(
    String mode,
    Future<T> Function(_IDBObjectStore store) run,
  ) async {
    final db = await _openDatabase();
    final transaction = db.transaction(_storeName.toJS, mode.toJS);
    final completed = _waitForTransaction(transaction);
    try {
      final result = await run(transaction.objectStore(_storeName.toJS));
      await completed;
      return result;
    } on Object {
      await completed.catchError((Object _) {});
      rethrow;
    }
  }

  Future<_IDBDatabase> _openDatabase() {
    final existing = _db;
    if (existing != null) return Future<_IDBDatabase>.value(existing);

    final opening = _opening;
    if (opening != null) return opening;

    final factory = _indexedDb;
    if (factory == null) {
      return Future<_IDBDatabase>.error(
        StateError('IndexedDB is not available in this browser context.'),
      );
    }

    final request = factory.open(databaseName.toJS, _schemaVersion.toJS);
    request.onupgradeneeded = ((JSAny _) {
      final db = request.result;
      if (!db.objectStoreNames.contains(_storeName.toJS)) {
        db.createObjectStore(_storeName.toJS);
      }
    }).toJS;

    final future = _waitForOpenRequest(request).then((db) {
      if (!db.objectStoreNames.contains(_storeName.toJS)) {
        db.close();
        throw StateError(
          'IndexedDB database "$databaseName" is missing the "$_storeName" '
          'object store required by schema version $_schemaVersion.',
        );
      }
      db.onversionchange = ((JSAny _) {
        close();
      }).toJS;
      _db = db;
      _opening = null;
      return db;
    }).catchError((Object error) {
      _opening = null;
      throw error;
    });

    _opening = future;
    return future;
  }

  static Future<_IDBDatabase> _waitForOpenRequest(
    _IDBOpenDBRequest request, {
    bool allowBlocked = false,
  }) {
    final completer = Completer<_IDBDatabase>();
    request.onsuccess = ((JSAny _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((JSAny _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(_describeDomError('IndexedDB open failed', request.error)),
          StackTrace.current,
        );
      }
    }).toJS;
    request.onblocked = ((JSAny _) {
      if (!allowBlocked && !completer.isCompleted) {
        completer.completeError(
          StateError(
              'IndexedDB open/delete was blocked by another connection.'),
          StackTrace.current,
        );
      }
    }).toJS;
    return completer.future;
  }

  static Future<void> _waitForDeleteDatabaseRequest(
    _IDBOpenDBRequest request,
  ) {
    final completer = Completer<void>();
    request.onsuccess = ((JSAny _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    request.onerror = ((JSAny _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            _describeDomError('IndexedDB delete failed', request.error),
          ),
          StackTrace.current,
        );
      }
    }).toJS;
    request.onblocked = ((JSAny _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('IndexedDB delete was blocked by another connection.'),
          StackTrace.current,
        );
      }
    }).toJS;
    return completer.future;
  }

  static Future<JSAny?> _waitForRequest(_IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((JSAny _) {
      if (!completer.isCompleted) completer.complete(request.result);
    }).toJS;
    request.onerror = ((JSAny _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            _describeDomError('IndexedDB request failed', request.error),
          ),
          StackTrace.current,
        );
      }
    }).toJS;
    return completer.future;
  }

  static Future<void> _waitForTransaction(_IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((JSAny _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    transaction.onerror = ((JSAny _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            _describeDomError(
              'IndexedDB transaction failed',
              transaction.error,
            ),
          ),
          StackTrace.current,
        );
      }
    }).toJS;
    transaction.onabort = ((JSAny _) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError(
            _describeDomError(
              'IndexedDB transaction aborted',
              transaction.error,
            ),
          ),
          StackTrace.current,
        );
      }
    }).toJS;
    return completer.future;
  }

  static String _describeDomError(String prefix, _DOMException? error) {
    if (error == null) return prefix;
    final name = error.name.toDart;
    final message = error.message.toDart;
    if (message.isEmpty) return '$prefix: $name';
    return '$prefix: $name: $message';
  }
}
