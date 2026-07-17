import 'dart:async';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

class _FailingSaveStorage implements AllBoxStorage {
  Map<String, dynamic>? persisted;
  int saveCalls = 0;
  int failuresRemaining = 0;

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
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw AllBoxStorageException('save failed');
    }
    persisted = Map<String, dynamic>.of(snapshot);
  }

  @override
  Future<void> delete() async {
    persisted = null;
  }

  @override
  Future<void> close() async {}
}

void main() {
  group('persistence error reporting', () {
    test('reports debounced write failures without unhandled async errors',
        () async {
      const container = 'persistence_error_debounced';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _FailingSaveStorage();
      final errors = <AllBoxPersistenceError>[];
      final uncaught = <Object>[];

      await runZonedGuarded(() async {
        final box = await AllBox.init(
          container,
          storage: storage,
          flushDelay: const Duration(milliseconds: 10),
          onPersistenceError: errors.add,
        );

        storage.failuresRemaining = 1;
        box.write('key', 'value');
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(box.read<String>('key'), 'value');
        expect(storage.persisted, isNull);
        expect(errors, hasLength(1));
        expect(errors.single.container, container);
        expect(errors.single.operation, 'write');
        expect(errors.single.cause, isA<AllBoxStorageException>());
        expect(errors.single.hasUnpersistedChanges, isTrue);

        box.write('key', 'recovered');
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(storage.persisted, {'key': 'recovered'});
        expect(errors, hasLength(1));
      }, (error, stack) {
        uncaught.add(error);
      });

      expect(uncaught, isEmpty);
    });

    test('reports writeAndSave failures and keeps the queue usable', () async {
      const container = 'persistence_error_save';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _FailingSaveStorage();
      final errors = <AllBoxPersistenceError>[];
      final box = await AllBox.init(
        container,
        storage: storage,
        onPersistenceError: errors.add,
      );

      storage.failuresRemaining = 1;
      await expectLater(
        box.writeAndSave('key', 'value'),
        throwsA(isA<AllBoxStorageException>()),
      );

      expect(errors, hasLength(1));
      expect(errors.single.operation, 'writeAndSave');
      expect(errors.single.hasUnpersistedChanges, isTrue);

      await box.writeAndSave('key', 'recovered');
      expect(storage.persisted, {'key': 'recovered'});
      expect(errors, hasLength(1));
    });

    test('reports writeAndFlush failures and keeps the queue usable', () async {
      const container = 'persistence_error_flush';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _FailingSaveStorage();
      final errors = <AllBoxPersistenceError>[];
      final box = await AllBox.init(
        container,
        storage: storage,
        onPersistenceError: errors.add,
      );

      storage.failuresRemaining = 1;
      await expectLater(
        box.writeAndFlush('key', 'value'),
        throwsA(isA<AllBoxStorageException>()),
      );

      expect(errors, hasLength(1));
      expect(errors.single.operation, 'writeAndFlush');
      expect(errors.single.hasUnpersistedChanges, isTrue);

      await box.writeAndFlush('key', 'recovered');
      expect(storage.persisted, {'key': 'recovered'});
      expect(errors, hasLength(1));
    });
  });
}
