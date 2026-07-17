import 'dart:async';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

class _SeedRetryStorage implements AllBoxStorage {
  int hasPersistedDataCalls = 0;
  int loadCalls = 0;
  int saveCalls = 0;
  Map<String, dynamic>? persisted;

  @override
  Future<bool> hasPersistedData() async {
    hasPersistedDataCalls++;
    return persisted != null;
  }

  @override
  Future<Map<String, dynamic>> load() async {
    loadCalls++;
    return Map<String, dynamic>.of(persisted ?? const <String, dynamic>{});
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    saveCalls++;
    if (saveCalls == 1) {
      throw AllBoxStorageException('seed save failed');
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

class _ControlledLoadStorage implements AllBoxStorage {
  final Completer<Map<String, dynamic>> loadCompleter =
      Completer<Map<String, dynamic>>();

  int hasPersistedDataCalls = 0;
  int loadCalls = 0;
  int saveCalls = 0;

  @override
  Future<bool> hasPersistedData() async {
    hasPersistedDataCalls++;
    return true;
  }

  @override
  Future<Map<String, dynamic>> load() {
    loadCalls++;
    return loadCompleter.future;
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    saveCalls++;
  }

  @override
  Future<void> delete() async {}

  @override
  Future<void> close() async {}
}

void main() {
  group('AllBox.init regression', () {
    test('rolls back completely when first-run seed persistence fails',
        () async {
      const container = 'init_seed_failure_rolls_back';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _SeedRetryStorage();

      await expectLater(
        AllBox.init(
          container,
          storage: storage,
          initialData: const {'seed': 'value'},
        ),
        throwsA(isA<AllBoxStorageException>()),
      );

      expect(AllBox(container).isInitialized, isFalse);

      final retried = await AllBox.init(
        container,
        storage: storage,
        initialData: const {'seed': 'value'},
      );

      expect(identical(retried, AllBox(container)), isTrue);
      expect(retried.isInitialized, isTrue);
      expect(retried.read<String>('seed'), 'value');
      expect(storage.saveCalls, 2);
      expect(storage.persisted, {'seed': 'value'});
    });

    test('shares one in-flight initialization for concurrent equal calls',
        () async {
      const container = 'init_concurrent_same_config';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledLoadStorage();

      final futures = Future.wait(<Future<AllBox>>[
        AllBox.init(container, storage: storage),
        AllBox.init(container, storage: storage),
        AllBox.init(container, storage: storage),
      ]);

      await Future<void>.delayed(Duration.zero);
      expect(storage.hasPersistedDataCalls, 1);
      expect(storage.loadCalls, 1);

      storage.loadCompleter.complete(<String, dynamic>{'loaded': true});
      final boxes = await futures;

      expect(identical(boxes[0], boxes[1]), isTrue);
      expect(identical(boxes[0], boxes[2]), isTrue);
      expect(boxes[0].read<bool>('loaded'), isTrue);
      expect(storage.saveCalls, 0);
    });

    test('rejects concurrent initialization with incompatible options',
        () async {
      const container = 'init_concurrent_conflicting_config';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final firstStorage = _ControlledLoadStorage();
      final secondStorage = _ControlledLoadStorage();

      final first = AllBox.init(
        container,
        storage: firstStorage,
        initialData: const {'seed': 1},
      );
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        AllBox.init(
          container,
          storage: secondStorage,
          initialData: const {'seed': 2},
          flushDelay: const Duration(seconds: 1),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('different options'),
          ),
        ),
      );

      firstStorage.loadCompleter.complete(<String, dynamic>{'loaded': true});
      await first;
    });

    test('rejects concurrent initialization with different IndexedDB opt-in',
        () async {
      const container = 'init_concurrent_indexed_db_option_conflict';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledLoadStorage();

      final first = AllBox.init(container, storage: storage);
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        AllBox.init(
          container,
          storage: storage,
          experimentalIndexedDbBackend: true,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('experimentalIndexedDbBackend'),
          ),
        ),
      );

      storage.loadCompleter.complete(<String, dynamic>{'loaded': true});
      await first;
    });
  });
}
