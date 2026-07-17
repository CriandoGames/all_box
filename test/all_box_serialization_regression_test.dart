import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

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
  group('non-JSON-encodable values on IO', () {
    test('debounced write reports the persistence failure via callback',
        () async {
      const container = 'serialization_debounced_io';
      final dir = await _tempDir(container);
      final errors = <AllBoxPersistenceError>[];
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        final box = await AllBox.init(
          container,
          path: dir.path,
          flushDelay: const Duration(milliseconds: 10),
          onPersistenceError: errors.add,
        );

        box.write('when', DateTime(2026));
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(box.read<DateTime>('when'), DateTime(2026));
        expect(errors, hasLength(1));
        expect(errors.single.container, container);
        expect(errors.single.operation, 'write');
        expect(errors.single.cause, isA<AllBoxStorageException>());
        expect(errors.single.hasUnpersistedChanges, isTrue);
        expect(File('${dir.path}/$container.db').existsSync(), isFalse);
      }, (error, stack) {
        uncaught.add(error);
      });

      expect(uncaught, isEmpty);
    });

    test('writeAndSave throws and reports invalid nested values', () async {
      const container = 'serialization_save_io';
      final dir = await _tempDir(container);
      final errors = <AllBoxPersistenceError>[];
      final box = await AllBox.init(
        container,
        path: dir.path,
        onPersistenceError: errors.add,
      );

      await expectLater(
        box.writeAndSave('payload', <String, dynamic>{
          'items': <dynamic>[DateTime(2026)],
        }),
        throwsA(isA<AllBoxStorageException>()),
      );

      expect(errors, hasLength(1));
      expect(errors.single.operation, 'writeAndSave');
    });

    test('writeAndFlush throws and reports invalid map values', () async {
      const container = 'serialization_flush_io';
      final dir = await _tempDir(container);
      final errors = <AllBoxPersistenceError>[];
      final box = await AllBox.init(
        container,
        path: dir.path,
        onPersistenceError: errors.add,
      );

      await expectLater(
        box.writeAndFlush('payload', <String, dynamic>{
          'invalid': Object(),
        }),
        throwsA(isA<AllBoxStorageException>()),
      );

      expect(errors, hasLength(1));
      expect(errors.single.operation, 'writeAndFlush');
    });
  });
}
