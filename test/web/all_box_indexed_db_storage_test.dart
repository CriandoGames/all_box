import 'package:test/test.dart';

import 'package:all_box/src/core/storage/all_box_indexed_db_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage_exception.dart';

class _FakeIndexedDbDriver implements AllBoxIndexedDbDriver {
  final Map<String, String> _records = <String, String>{};

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
    return _records.containsKey(container);
  }

  @override
  Future<String?> read(String container) async {
    final error = readError;
    if (error != null) throw error();
    return _records[container];
  }

  @override
  Future<void> write(String container, String jsonText) async {
    final error = writeError;
    if (error != null) throw error();
    _records[container] = jsonText;
  }

  @override
  Future<String> update(
    String container,
    String Function(String? currentJsonText) merge,
  ) async {
    final error = writeError;
    if (error != null) throw error();
    final next = merge(_records[container]);
    _records[container] = next;
    return next;
  }

  @override
  Future<void> delete(String container) async {
    final error = deleteError;
    if (error != null) throw error();
    _records.remove(container);
  }

  @override
  Future<void> close() async {
    final error = closeError;
    if (error != null) throw error();
    closed = true;
  }
}

void main() {
  group('AllBoxIndexedDbStorage', () {
    test('hasPersistedData is false before save and true after', () async {
      final driver = _FakeIndexedDbDriver();
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      expect(await storage.hasPersistedData(), isFalse);

      await storage.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);

      expect(await storage.hasPersistedData(), isTrue);
    });

    test('load returns empty when the container is absent', () async {
      final storage = AllBoxIndexedDbStorage(
        container: 'missing',
        driver: _FakeIndexedDbDriver(),
      );

      expect(await storage.load(), isEmpty);
    });

    test('save then load round-trips a JSON snapshot', () async {
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: _FakeIndexedDbDriver(),
      );

      await storage.save(
        <String, dynamic>{
          'theme': 'dark',
          'count': 3,
          'nested': <String, dynamic>{'enabled': true},
        },
        mode: AllBoxPersistMode.save,
      );

      expect(await storage.load(), <String, dynamic>{
        'theme': 'dark',
        'count': 3,
        'nested': <String, dynamic>{'enabled': true},
      });
    });

    test('merge preserves different keys written by another instance',
        () async {
      final driver = _FakeIndexedDbDriver();
      final first = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      final second = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      expect(await first.load(), isEmpty);
      expect(await second.load(), isEmpty);

      await first.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await second.save({'token': 'abc'}, mode: AllBoxPersistMode.flush);

      final reloaded = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      expect(await reloaded.load(), {'theme': 'dark', 'token': 'abc'});
    });

    test('same-key conflict uses last write wins', () async {
      final driver = _FakeIndexedDbDriver();
      final first = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      final second = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      await first.load();
      await second.load();

      await first.save({'theme': 'dark'}, mode: AllBoxPersistMode.flush);
      await second.save({'theme': 'light'}, mode: AllBoxPersistMode.flush);

      final reloaded = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      expect(await reloaded.load(), {'theme': 'light'});
    });

    test('unchanged local keys preserve newer remote values', () async {
      final driver = _FakeIndexedDbDriver()
        .._records['settings'] = '{"theme":"old","count":1}';
      final first = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      final second = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      expect(await first.load(), {'theme': 'old', 'count': 1});
      expect(await second.load(), {'theme': 'old', 'count': 1});

      await second.save(
        {'theme': 'new', 'count': 1},
        mode: AllBoxPersistMode.flush,
      );
      await first.save(
        {'theme': 'old', 'count': 1, 'localOnly': true},
        mode: AllBoxPersistMode.flush,
      );

      final reloaded = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      expect(await reloaded.load(), {
        'theme': 'new',
        'count': 1,
        'localOnly': true,
      });
    });

    test('removed local key wins over newer remote value for that key',
        () async {
      final driver = _FakeIndexedDbDriver()
        .._records['settings'] = '{"theme":"old","count":1}';
      final first = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      final second = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      await first.load();
      await second.load();

      await second.save(
        {'theme': 'new', 'count': 1},
        mode: AllBoxPersistMode.flush,
      );
      await first.save({'count': 1}, mode: AllBoxPersistMode.flush);

      final reloaded = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );
      expect(await reloaded.load(), {'count': 1});
    });

    test('load falls back to empty on invalid JSON', () async {
      final driver = _FakeIndexedDbDriver();
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      await driver.write('settings', '{ not json ][');

      expect(await storage.load(), isEmpty);
    });

    test('load falls back to empty when the driver read fails', () async {
      final driver = _FakeIndexedDbDriver()
        ..readError = () => StateError('IndexedDB unavailable');
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      expect(await storage.load(), isEmpty);
    });

    test('save throws AllBoxStorageException on non-JSON values', () async {
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: _FakeIndexedDbDriver(),
      );

      await expectLater(
        storage.save({'when': DateTime(2026)}, mode: AllBoxPersistMode.flush),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('save/delete/contains/close wrap driver failures', () async {
      final driver = _FakeIndexedDbDriver();
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      driver.containsError = () => StateError('boom');
      await expectLater(
        storage.hasPersistedData(),
        throwsA(isA<AllBoxStorageException>()),
      );
      driver.containsError = null;

      driver.writeError = () => StateError('boom');
      await expectLater(
        storage.save({'a': 1}, mode: AllBoxPersistMode.flush),
        throwsA(isA<AllBoxStorageException>()),
      );
      driver.writeError = null;

      driver.deleteError = () => StateError('boom');
      await expectLater(
        storage.delete(),
        throwsA(isA<AllBoxStorageException>()),
      );
      driver.deleteError = null;

      driver.closeError = () => StateError('boom');
      await expectLater(
        storage.close(),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('delete removes the saved record and close delegates to the driver',
        () async {
      final driver = _FakeIndexedDbDriver();
      final storage = AllBoxIndexedDbStorage(
        container: 'settings',
        driver: driver,
      );

      await storage.save({'a': 1}, mode: AllBoxPersistMode.flush);
      expect(await storage.hasPersistedData(), isTrue);

      await storage.delete();
      expect(await storage.hasPersistedData(), isFalse);

      await storage.close();
      expect(driver.closed, isTrue);
    });
  });
}
