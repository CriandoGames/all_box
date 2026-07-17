import 'dart:io';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

class _LifecycleStorage implements AllBoxStorage {
  _LifecycleStorage([Map<String, dynamic>? initial])
      : persisted = initial == null ? null : Map<String, dynamic>.of(initial);

  Map<String, dynamic>? persisted;
  int saveCalls = 0;
  int deleteCalls = 0;
  int closeCalls = 0;

  @override
  Future<bool> hasPersistedData() async => persisted != null;

  @override
  Future<Map<String, dynamic>> load() async {
    return Map<String, dynamic>.of(persisted ?? const <String, dynamic>{});
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    saveCalls++;
    persisted = Map<String, dynamic>.of(snapshot);
  }

  @override
  Future<void> delete() async {
    deleteCalls++;
    persisted = null;
  }

  @override
  Future<void> close() async {
    closeCalls++;
  }
}

Future<Directory> _tempDir(String label) async {
  final dir = await Directory.systemTemp.createTemp('all_box_${label}_');
  addTearDown(() async {
    AllBox.resetInstanceForTesting(label);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

void main() {
  group('AllBox lifecycle', () {
    test('close flushes pending data, closes storage once and unregisters',
        () async {
      const container = 'lifecycle_close_flushes';
      final storage = _LifecycleStorage(null);
      final box = await AllBox.init(
        container,
        storage: storage,
        flushDelay: const Duration(seconds: 5),
      );

      box.write('pending', true);
      await box.close();
      await box.close();

      expect(storage.persisted, {'pending': true});
      expect(storage.closeCalls, 1);
      expect(box.isInitialized, isFalse);
      expect(() => box.write('after', false), throwsStateError);

      final reopened = await AllBox.init(container, storage: storage);
      expect(identical(reopened, box), isFalse);
      expect(reopened.read<bool>('pending'), isTrue);
    });

    test('close can discard a pending debounced write', () async {
      const container = 'lifecycle_close_discard';
      final storage = _LifecycleStorage(<String, dynamic>{});
      final box = await AllBox.init(
        container,
        storage: storage,
        flushDelay: const Duration(seconds: 5),
      );

      box.write('pending', true);
      await box.close(flushPending: false);

      expect(storage.persisted, isEmpty);
      expect(storage.closeCalls, 1);
    });

    test('destroy deletes persisted data, closes storage and unregisters',
        () async {
      const container = 'lifecycle_destroy';
      final storage = _LifecycleStorage(<String, dynamic>{'old': true});
      final box = await AllBox.init(container, storage: storage);

      await box.destroy();

      expect(storage.deleteCalls, 1);
      expect(storage.closeCalls, 1);
      expect(storage.persisted, isNull);
      expect(box.isInitialized, isFalse);

      final reopened = await AllBox.init(container, storage: storage);
      expect(identical(reopened, box), isFalse);
      expect(reopened.getKeys(), isEmpty);
    });

    test('destroy removes db/tmp/bak files on IO', () async {
      const container = 'lifecycle_destroy_io';
      final dir = await _tempDir(container);
      final box = await AllBox.init(container, path: dir.path);

      await box.writeAndFlush('token', 'old-value');
      await box.writeAndFlush('token', 'new-value');
      await File('${dir.path}/$container.tmp').writeAsString('stale');

      await box.destroy();

      expect(File('${dir.path}/$container.db').existsSync(), isFalse);
      expect(File('${dir.path}/$container.tmp').existsSync(), isFalse);
      expect(File('${dir.path}/$container.bak').existsSync(), isFalse);
    });
  });

  group('IO container name validation', () {
    for (final invalid in <String>[
      '',
      '../outside',
      '../../data',
      'a/b',
      r'a\b',
      '.',
      '..',
      'CON',
      'NUL',
      'cache:name',
    ]) {
      test('rejects invalid container name "$invalid" in strict mode',
          () async {
        final dir = await _tempDir('invalid_name_${invalid.hashCode}');

        await expectLater(
          AllBox.init(invalid, path: dir.path, validateContainerName: true),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.message,
              'message',
              contains('letters, numbers, ".", "_" or "-"'),
            ),
          ),
        );

        expect(dir.listSync(), isEmpty);
      });
    }

    test('keeps legacy container names accepted by default', () async {
      const container = 'legacy/user-cache';
      final dir = await _tempDir('legacy_container_name_default');
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await expectLater(AllBox.init(container, path: dir.path), completes);
    });

    test('keeps existing simple names valid', () async {
      const container = 'valid_container-01.cache';
      final dir = await _tempDir(container);

      final box = await AllBox.init(container,
          path: dir.path, validateContainerName: true);
      await box.writeAndFlush('ok', true);

      expect(File('${dir.path}/$container.db').existsSync(), isTrue);
    });
  });
}
