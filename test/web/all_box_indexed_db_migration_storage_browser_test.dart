@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:test/test.dart';

import 'package:all_box/src/core/storage/all_box_indexed_db_migration_storage.dart';
import 'package:all_box/src/core/storage/all_box_indexed_db_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage.dart';
import 'package:all_box/src/core/storage/all_box_web_storage.dart';
import 'package:all_box/src/core/storage/platform/all_box_indexed_db_browser.dart';

extension type _JSStorage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

@JS('window.localStorage')
external _JSStorage get _localStorage;

class _BrowserLegacyStorage implements AllBoxBrowserStorage {
  @override
  String? getItem(String key) => _localStorage.getItem(key.toJS)?.toDart;

  @override
  void setItem(String key, String value) {
    _localStorage.setItem(key.toJS, value.toJS);
  }

  @override
  void removeItem(String key) {
    _localStorage.removeItem(key.toJS);
  }
}

class _ThrowingIndexedDbDriver implements AllBoxIndexedDbDriver {
  @override
  Future<bool> contains(String container) async {
    throw StateError('IndexedDB unavailable');
  }

  @override
  Future<String?> read(String container) async {
    throw StateError('IndexedDB unavailable');
  }

  @override
  Future<void> write(String container, String jsonText) async {
    throw StateError('IndexedDB unavailable');
  }

  @override
  Future<String> update(
    String container,
    String Function(String? currentJsonText) merge,
  ) async {
    throw StateError('IndexedDB unavailable');
  }

  @override
  Future<void> delete(String container) async {
    throw StateError('IndexedDB unavailable');
  }

  @override
  Future<void> close() async {}
}

class _ToggleIndexedDbDriver implements AllBoxIndexedDbDriver {
  _ToggleIndexedDbDriver(this.delegate);

  final AllBoxIndexedDbDriver delegate;
  bool failUpdates = false;

  @override
  Future<bool> contains(String container) => delegate.contains(container);

  @override
  Future<String?> read(String container) => delegate.read(container);

  @override
  Future<void> write(String container, String jsonText) {
    return delegate.write(container, jsonText);
  }

  @override
  Future<String> update(
    String container,
    String Function(String? currentJsonText) merge,
  ) {
    if (failUpdates) {
      return Future<String>.error(StateError('IndexedDB update unavailable'));
    }
    return delegate.update(container, merge);
  }

  @override
  Future<void> delete(String container) => delegate.delete(container);

  @override
  Future<void> close() => delegate.close();
}

void main() {
  group('AllBoxIndexedDbMigrationStorage (real browser)', () {
    late String databaseName;
    late _BrowserLegacyStorage legacy;

    setUp(() async {
      databaseName = 'all_box_indexed_db_migration_test_'
          '${DateTime.now().microsecondsSinceEpoch}';
      legacy = _BrowserLegacyStorage();
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting(databaseName);
    });

    tearDown(() async {
      for (final container in <String>['settings', 'cache']) {
        legacy.removeItem('all_box::$container');
        legacy.removeItem(
          'all_box_internal::indexeddb_fallback::'
          '${Uri.encodeComponent(container)}',
        );
      }
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting(databaseName);
    });

    AllBoxIndexedDbMigrationStorage storage(String container) {
      return AllBoxIndexedDbMigrationStorage(
        container: container,
        indexedDb: AllBoxBrowserIndexedDbDriver(databaseName: databaseName),
        legacyStorage: legacy,
      );
    }

    test('migrates legacy localStorage into IndexedDB and removes legacy copy',
        () async {
      legacy.setItem('all_box::settings', '{"theme":"legacy"}');

      final migrating = storage('settings');
      expect(await migrating.load(), {'theme': 'legacy'});
      expect(legacy.getItem('all_box::settings'), isNull);
      await migrating.close();

      final reloaded = storage('settings');
      expect(await reloaded.load(), {'theme': 'legacy'});
      await reloaded.close();
    });

    test('IndexedDB data wins over stale legacy localStorage data', () async {
      final first = storage('settings');
      await first.save({'theme': 'indexed'}, mode: AllBoxPersistMode.flush);
      await first.close();

      legacy.setItem('all_box::settings', '{"theme":"legacy"}');

      final second = storage('settings');
      expect(await second.load(), {'theme': 'indexed'});
      expect(legacy.getItem('all_box::settings'), '{"theme":"legacy"}');
      await second.close();
    });

    test('merges different keys written by separate migrated instances',
        () async {
      final first = storage('settings');
      final second = storage('settings');

      expect(await first.load(), isEmpty);
      expect(await second.load(), isEmpty);

      await first.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await second.save({'token': 'abc'}, mode: AllBoxPersistMode.flush);
      await first.close();
      await second.close();

      final reloaded = storage('settings');
      expect(await reloaded.load(), {'theme': 'dark', 'token': 'abc'});
      await reloaded.close();
    });

    test('uses last write wins for the same migrated key', () async {
      final first = storage('settings');
      final second = storage('settings');

      await first.load();
      await second.load();

      await first.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await second.save({'theme': 'light'}, mode: AllBoxPersistMode.flush);
      await first.close();
      await second.close();

      final reloaded = storage('settings');
      expect(await reloaded.load(), {'theme': 'light'});
      await reloaded.close();
    });

    test('save uses legacy localStorage fallback when IndexedDB is unavailable',
        () async {
      final fallback = AllBoxIndexedDbMigrationStorage(
        container: 'cache',
        indexedDb: _ThrowingIndexedDbDriver(),
        legacyStorage: legacy,
      );

      await fallback.save({'page': 1}, mode: AllBoxPersistMode.flush);

      expect(legacy.getItem('all_box::cache'), '{"page":1}');
    });

    test('load uses legacy localStorage fallback when IndexedDB is unavailable',
        () async {
      legacy.setItem('all_box::cache', '{"page":2}');
      final fallback = AllBoxIndexedDbMigrationStorage(
        container: 'cache',
        indexedDb: _ThrowingIndexedDbDriver(),
        legacyStorage: legacy,
      );

      expect(await fallback.load(), {'page': 2});
      expect(legacy.getItem('all_box::cache'), '{"page":2}');
    });

    test('recovers a fallback into real IndexedDB in the same instance',
        () async {
      final driver = _ToggleIndexedDbDriver(
        AllBoxBrowserIndexedDbDriver(databaseName: databaseName),
      );
      final migrating = AllBoxIndexedDbMigrationStorage(
        container: 'settings',
        indexedDb: driver,
        legacyStorage: legacy,
      );

      await migrating.save({'theme': 'old'}, mode: AllBoxPersistMode.flush);
      expect(await migrating.load(), {'theme': 'old'});
      driver.failUpdates = true;
      await migrating.save({'theme': 'new'}, mode: AllBoxPersistMode.flush);
      expect(legacy.getItem('all_box::settings'), '{"theme":"new"}');

      driver.failUpdates = false;
      await migrating.save({'theme': 'new'}, mode: AllBoxPersistMode.flush);
      expect(await migrating.load(), {'theme': 'new'});
      expect(legacy.getItem('all_box::settings'), isNull);
      await migrating.close();
    });

    test('recovers a fallback into real IndexedDB after reload', () async {
      final firstDriver = _ToggleIndexedDbDriver(
        AllBoxBrowserIndexedDbDriver(databaseName: databaseName),
      );
      final first = AllBoxIndexedDbMigrationStorage(
        container: 'settings',
        indexedDb: firstDriver,
        legacyStorage: legacy,
      );

      await first.save({'theme': 'old'}, mode: AllBoxPersistMode.flush);
      await first.load();
      firstDriver.failUpdates = true;
      await first.save({'theme': 'new'}, mode: AllBoxPersistMode.flush);
      await first.close();

      final reloaded = storage('settings');
      expect(await reloaded.load(), {'theme': 'new'});
      expect(legacy.getItem('all_box::settings'), isNull);
      await reloaded.close();
    });
  });
}
