import 'package:test/test.dart';

import 'package:all_box/src/core/storage/all_box_indexed_db_migration_storage.dart';
import 'package:all_box/src/core/storage/all_box_indexed_db_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage_exception.dart';
import 'package:all_box/src/core/storage/all_box_web_storage.dart';

class _FakeIndexedDbDriver implements AllBoxIndexedDbDriver {
  final Map<String, String> records = <String, String>{};

  Object Function()? containsError;
  Object Function()? readError;
  Object Function()? writeError;
  Object Function()? deleteError;
  Object Function()? closeError;

  bool closed = false;

  @override
  Future<bool> contains(String container) async {
    final error = containsError;
    if (error != null) throw error();
    return records.containsKey(container);
  }

  @override
  Future<String?> read(String container) async {
    final error = readError;
    if (error != null) throw error();
    return records[container];
  }

  @override
  Future<void> write(String container, String jsonText) async {
    final error = writeError;
    if (error != null) throw error();
    records[container] = jsonText;
  }

  @override
  Future<String> update(
    String container,
    String Function(String? currentJsonText) merge,
  ) async {
    final error = writeError;
    if (error != null) throw error();
    final next = merge(records[container]);
    records[container] = next;
    return next;
  }

  @override
  Future<void> delete(String container) async {
    final error = deleteError;
    if (error != null) throw error();
    records.remove(container);
  }

  @override
  Future<void> close() async {
    final error = closeError;
    if (error != null) throw error();
    closed = true;
  }
}

class _FakeLegacyStorage implements AllBoxBrowserStorage {
  final Map<String, String> records = <String, String>{};

  Object Function()? getError;
  Object Function()? setError;
  Object Function()? removeError;

  @override
  String? getItem(String key) {
    final error = getError;
    if (error != null) throw error();
    return records[key];
  }

  @override
  void setItem(String key, String value) {
    final error = setError;
    if (error != null) throw error();
    records[key] = value;
  }

  @override
  void removeItem(String key) {
    final error = removeError;
    if (error != null) throw error();
    records.remove(key);
  }
}

void main() {
  group('AllBoxIndexedDbMigrationStorage', () {
    const container = 'settings';
    const legacyKey = 'all_box::$container';

    AllBoxIndexedDbMigrationStorage storage(
      _FakeIndexedDbDriver indexedDb,
      _FakeLegacyStorage legacy,
    ) {
      return AllBoxIndexedDbMigrationStorage(
        container: container,
        indexedDb: indexedDb,
        legacyStorage: legacy,
      );
    }

    test('loads IndexedDB data before legacy localStorage data', () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..records[container] = '{"source":"indexed"}';
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"source":"legacy"}';

      final loaded = await storage(indexedDb, legacy).load();

      expect(loaded, {'source': 'indexed'});
      expect(legacy.records[legacyKey], '{"source":"legacy"}');
    });

    test('migrates legacy localStorage data and removes it after success',
        () async {
      final indexedDb = _FakeIndexedDbDriver();
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"theme":"dark"}';

      final loaded = await storage(indexedDb, legacy).load();

      expect(loaded, {'theme': 'dark'});
      expect(indexedDb.records[container], '{"theme":"dark"}');
      expect(legacy.records.containsKey(legacyKey), isFalse);
    });

    test('keeps legacy localStorage intact when migration write fails',
        () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..writeError = () => StateError('IndexedDB write failed');
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"theme":"dark"}';

      final loaded = await storage(indexedDb, legacy).load();

      expect(loaded, {'theme': 'dark'});
      expect(indexedDb.records, isEmpty);
      expect(legacy.records[legacyKey], '{"theme":"dark"}');
    });

    test('falls back to legacy localStorage when IndexedDB read fails',
        () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..readError = () => StateError('IndexedDB unavailable');
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"theme":"dark"}';

      expect(await storage(indexedDb, legacy).load(), {'theme': 'dark'});
    });

    test('save writes IndexedDB and clears stale legacy data', () async {
      final indexedDb = _FakeIndexedDbDriver();
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"theme":"old"}';

      await storage(indexedDb, legacy).save(
        {'theme': 'new'},
        mode: AllBoxPersistMode.flush,
      );

      expect(indexedDb.records[container], '{"theme":"new"}');
      expect(legacy.records.containsKey(legacyKey), isFalse);
    });

    test('save merges different keys written by another migrated instance',
        () async {
      final indexedDb = _FakeIndexedDbDriver();
      final legacy = _FakeLegacyStorage();
      final first = storage(indexedDb, legacy);
      final second = storage(indexedDb, legacy);

      expect(await first.load(), isEmpty);
      expect(await second.load(), isEmpty);

      await first.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await second.save({'token': 'abc'}, mode: AllBoxPersistMode.flush);

      final reloaded = storage(indexedDb, legacy);
      expect(await reloaded.load(), {'theme': 'dark', 'token': 'abc'});
    });

    test('save uses last write wins for the same migrated key', () async {
      final indexedDb = _FakeIndexedDbDriver();
      final legacy = _FakeLegacyStorage();
      final first = storage(indexedDb, legacy);
      final second = storage(indexedDb, legacy);

      await first.load();
      await second.load();

      await first.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await second.save({'theme': 'light'}, mode: AllBoxPersistMode.flush);

      final reloaded = storage(indexedDb, legacy);
      expect(await reloaded.load(), {'theme': 'light'});
    });

    test('save falls back to legacy localStorage when IndexedDB write fails',
        () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..writeError = () => StateError('IndexedDB write failed');
      final legacy = _FakeLegacyStorage();

      await storage(indexedDb, legacy).save(
        {'theme': 'fallback'},
        mode: AllBoxPersistMode.flush,
      );

      expect(indexedDb.records, isEmpty);
      expect(legacy.records[legacyKey], '{"theme":"fallback"}');
    });

    test('save reports when IndexedDB and legacy fallback both fail', () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..writeError = () => StateError('IndexedDB write failed');
      final legacy = _FakeLegacyStorage()
        ..setError = () => StateError('localStorage write failed');

      await expectLater(
        storage(indexedDb, legacy).save(
          {'theme': 'dark'},
          mode: AllBoxPersistMode.flush,
        ),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('delete removes both stores when both are available', () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..records[container] = '{"theme":"dark"}';
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"theme":"old"}';

      await storage(indexedDb, legacy).delete();

      expect(indexedDb.records.containsKey(container), isFalse);
      expect(legacy.records.containsKey(legacyKey), isFalse);
    });

    test('delete removes legacy data but reports IndexedDB delete failure',
        () async {
      final indexedDb = _FakeIndexedDbDriver()
        ..records[container] = '{"theme":"dark"}'
        ..deleteError = () => StateError('IndexedDB delete failed');
      final legacy = _FakeLegacyStorage()
        ..records[legacyKey] = '{"theme":"old"}';

      await expectLater(
        storage(indexedDb, legacy).delete(),
        throwsA(isA<AllBoxStorageException>()),
      );

      expect(legacy.records.containsKey(legacyKey), isFalse);
      expect(indexedDb.records.containsKey(container), isTrue);
    });

    test('close delegates to IndexedDB driver', () async {
      final indexedDb = _FakeIndexedDbDriver();
      final legacy = _FakeLegacyStorage();

      await storage(indexedDb, legacy).close();

      expect(indexedDb.closed, isTrue);
    });
  });
}
