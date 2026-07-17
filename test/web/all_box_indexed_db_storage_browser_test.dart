@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';

import 'package:all_box/src/core/storage/all_box_indexed_db_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage_exception.dart';
import 'package:all_box/src/core/storage/platform/all_box_indexed_db_browser.dart';

@JS('indexedDB')
external _RawIDBFactory? get _indexedDb;

extension type _RawIDBFactory._(JSObject _) implements JSObject {
  external _RawIDBOpenDBRequest open(JSString name, JSNumber version);
}

extension type _RawDOMStringList._(JSObject _) implements JSObject {
  external bool contains(JSString value);
}

extension type _RawDOMException._(JSObject _) implements JSObject {
  external JSString get name;
  external JSString get message;
}

extension type _RawIDBOpenDBRequest._(JSObject _) implements JSObject {
  external set onsuccess(JSFunction? callback);
  external set onerror(JSFunction? callback);
  external _RawIDBDatabase get result;
  external _RawDOMException? get error;
}

extension type _RawIDBDatabase._(JSObject _) implements JSObject {
  external JSNumber get version;
  external _RawDOMStringList get objectStoreNames;
  external void close();
}

Future<_RawIDBDatabase> _openRawDatabase(
  String databaseName,
  int version,
) {
  final factory = _indexedDb;
  if (factory == null) {
    return Future<_RawIDBDatabase>.error(
      StateError('IndexedDB is not available in this browser context.'),
    );
  }

  final request = factory.open(databaseName.toJS, version.toJS);
  final completer = Completer<_RawIDBDatabase>();
  request.onsuccess = ((JSAny _) {
    if (!completer.isCompleted) completer.complete(request.result);
  }).toJS;
  request.onerror = ((JSAny _) {
    if (!completer.isCompleted) {
      completer.completeError(
        StateError(
            _describeRawDomError('Raw IndexedDB open failed', request.error)),
        StackTrace.current,
      );
    }
  }).toJS;
  return completer.future;
}

String _describeRawDomError(String prefix, _RawDOMException? error) {
  if (error == null) return prefix;
  final name = error.name.toDart;
  final message = error.message.toDart;
  if (message.isEmpty) return '$prefix: $name';
  return '$prefix: $name: $message';
}

void main() {
  group('AllBoxIndexedDbStorage (real browser)', () {
    late String databaseName;

    setUp(() async {
      databaseName =
          'all_box_indexed_db_test_${DateTime.now().microsecondsSinceEpoch}';
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting(databaseName);
    });

    tearDown(() async {
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting(databaseName);
    });

    AllBoxIndexedDbStorage storage(String container) {
      return AllBoxIndexedDbStorage(
        container: container,
        driver: AllBoxBrowserIndexedDbDriver(databaseName: databaseName),
      );
    }

    test('creates schema v1 and round-trips a container snapshot', () async {
      final boxStorage = storage('settings');

      expect(await boxStorage.hasPersistedData(), isFalse);

      await boxStorage.save(
        <String, dynamic>{
          'theme': 'dark',
          'count': 2,
          'nested': <String, dynamic>{'enabled': true},
        },
        mode: AllBoxPersistMode.flush,
      );

      expect(await boxStorage.hasPersistedData(), isTrue);
      expect(await boxStorage.load(), <String, dynamic>{
        'theme': 'dark',
        'count': 2,
        'nested': <String, dynamic>{'enabled': true},
      });

      await boxStorage.close();
    });

    test('creates the expected schema version and object store', () async {
      final boxStorage = storage('schema');
      await boxStorage.save({'ready': true}, mode: AllBoxPersistMode.flush);
      await boxStorage.close();

      final rawDb = await _openRawDatabase(
        databaseName,
        AllBoxBrowserIndexedDbDriver.schemaVersionForTesting,
      );
      // ignore: unnecessary_lambdas
      addTearDown(() {
        rawDb.close();
      });

      expect(
        rawDb.version.dartify(),
        AllBoxBrowserIndexedDbDriver.schemaVersionForTesting,
      );
      expect(
        rawDb.objectStoreNames.contains(
          AllBoxBrowserIndexedDbDriver.storeNameForTesting.toJS,
        ),
        isTrue,
      );
    });

    test('closes its connection on versionchange so database deletion can run',
        () async {
      final driver = AllBoxBrowserIndexedDbDriver(databaseName: databaseName);
      final boxStorage = AllBoxIndexedDbStorage(
        container: 'version_change',
        driver: driver,
      );

      await boxStorage.save({'before': true}, mode: AllBoxPersistMode.flush);

      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting(databaseName);

      expect(await boxStorage.hasPersistedData(), isFalse);
      await boxStorage.save({'after': true}, mode: AllBoxPersistMode.flush);
      expect(await boxStorage.load(), {'after': true});
      await boxStorage.close();
    });

    test('reports blocked database deletion instead of hanging', () async {
      final boxStorage = storage('blocked_delete');
      await boxStorage.save({'value': 1}, mode: AllBoxPersistMode.flush);
      await boxStorage.close();

      final rawDb = await _openRawDatabase(
        databaseName,
        AllBoxBrowserIndexedDbDriver.schemaVersionForTesting,
      );

      try {
        await expectLater(
          AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting(databaseName),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('blocked'),
            ),
          ),
        );
      } finally {
        rawDb.close();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    });

    test('reports incompatible schema when the containers store is missing',
        () async {
      final rawDb = await _openRawDatabase(
        databaseName,
        AllBoxBrowserIndexedDbDriver.schemaVersionForTesting,
      );
      rawDb.close();

      final boxStorage = storage('missing_store');
      await expectLater(
        boxStorage.hasPersistedData(),
        throwsA(
          isA<AllBoxStorageException>().having(
            (error) => error.cause.toString(),
            'cause',
            allOf(
              contains('missing'),
              contains(AllBoxBrowserIndexedDbDriver.storeNameForTesting),
            ),
          ),
        ),
      );
    });

    test('persists data across driver instances', () async {
      final first = storage('session');
      await first.save({'token': 'abc'}, mode: AllBoxPersistMode.flush);
      await first.close();

      final second = storage('session');
      expect(await second.hasPersistedData(), isTrue);
      expect(await second.load(), {'token': 'abc'});
      await second.close();
    });

    test('delete removes only the selected container', () async {
      final settings = storage('settings');
      final cache = storage('cache');

      await settings.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await cache.save({'page': 1}, mode: AllBoxPersistMode.flush);

      await settings.delete();

      expect(await settings.hasPersistedData(), isFalse);
      expect(await settings.load(), isEmpty);
      expect(await cache.load(), {'page': 1});

      await settings.close();
      await cache.close();
    });

    test('large snapshot round-trips through real IndexedDB', () async {
      final boxStorage = storage('large');
      final snapshot = <String, dynamic>{
        for (var i = 0; i < 5000; i++) 'key_$i': 'value_$i',
      };

      await boxStorage.save(snapshot, mode: AllBoxPersistMode.flush);

      final loaded = await boxStorage.load();
      expect(loaded.length, 5000);
      expect(loaded['key_0'], 'value_0');
      expect(loaded['key_4999'], 'value_4999');

      await boxStorage.close();
    });
  });
}
