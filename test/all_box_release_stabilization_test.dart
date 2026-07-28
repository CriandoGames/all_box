import 'dart:async';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

class _ControlledStorage implements AllBoxStorage {
  _ControlledStorage([Map<String, dynamic>? initial])
      : persisted = initial == null ? null : Map<String, dynamic>.of(initial);

  Map<String, dynamic>? persisted;
  int saveCalls = 0;
  int deleteCalls = 0;
  int closeCalls = 0;
  Object? hasPersistedDataError;
  Object? saveError;
  Object? deleteError;
  Object? closeError;
  Completer<Map<String, dynamic>>? blockedLoad;
  Completer<void>? blockedDelete;
  Completer<void>? blockedClose;
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> closeStarted = Completer<void>();

  @override
  Future<bool> hasPersistedData() async {
    if (hasPersistedDataError case final error?) throw error;
    return persisted != null;
  }

  @override
  Future<Map<String, dynamic>> load() {
    final blocked = blockedLoad;
    if (blocked != null) return blocked.future;
    return Future<Map<String, dynamic>>.value(
      Map<String, dynamic>.of(persisted ?? const <String, dynamic>{}),
    );
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    saveCalls++;
    if (saveError case final error?) throw error;
    persisted = Map<String, dynamic>.of(snapshot);
  }

  @override
  Future<void> delete() async {
    deleteCalls++;
    if (!deleteStarted.isCompleted) deleteStarted.complete();
    final blocked = blockedDelete;
    if (blocked != null) await blocked.future;
    if (deleteError case final error?) throw error;
    persisted = null;
  }

  @override
  Future<void> close() async {
    closeCalls++;
    if (!closeStarted.isCompleted) closeStarted.complete();
    final blocked = blockedClose;
    if (blocked != null) await blocked.future;
    if (closeError case final error?) throw error;
  }
}

void main() {
  group('release lifecycle stabilization', () {
    test('close without local changes does not overwrite external data',
        () async {
      const container = 'close_clean_does_not_save';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage({'counter': 1});
      final box = await AllBox.init(container, storage: storage);

      storage.persisted = {'counter': 2};
      await box.close();

      expect(storage.saveCalls, 0);
      expect(storage.persisted, {'counter': 2});
      expect(storage.closeCalls, 1);
    });

    test('write followed by close still persists the pending write', () async {
      const container = 'close_dirty_still_saves';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage(<String, dynamic>{});
      final box = await AllBox.init(
        container,
        storage: storage,
        flushDelay: const Duration(seconds: 10),
      );

      box.write('counter', 1);
      await box.close();

      expect(storage.saveCalls, 1);
      expect(storage.persisted, {'counter': 1});
    });

    test('write is rejected as soon as close starts', () async {
      const container = 'write_during_close';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage(<String, dynamic>{})
        ..blockedClose = Completer<void>();
      final box = await AllBox.init(container, storage: storage);

      final closing = box.close();
      await storage.closeStarted.future;

      expect(() => box.write('late', true), throwsStateError);
      storage.blockedClose!.complete();
      await closing;
      expect(storage.saveCalls, 0);
    });

    test('mutations are rejected while destroy is waiting for delete',
        () async {
      const container = 'mutations_during_destroy';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage({'old': true})
        ..blockedDelete = Completer<void>();
      final box = await AllBox.init(container, storage: storage);

      final destroying = box.destroy();
      await storage.deleteStarted.future;

      expect(() => box.write('late', true), throwsStateError);
      expect(() => box.remove('old'), throwsStateError);
      expect(box.erase, throwsStateError);
      storage.blockedDelete!.complete();
      await destroying;

      expect(storage.persisted, isNull);
      expect(storage.saveCalls, 0);
      expect(storage.closeCalls, 1);
    });

    test('concurrent equal lifecycle calls share one cleanup', () async {
      const closeContainer = 'concurrent_close';
      const destroyContainer = 'concurrent_destroy';
      addTearDown(() {
        AllBox.resetInstanceForTesting(closeContainer);
        AllBox.resetInstanceForTesting(destroyContainer);
      });

      final closeStorage = _ControlledStorage(<String, dynamic>{})
        ..blockedClose = Completer<void>();
      final closeBox = await AllBox.init(closeContainer, storage: closeStorage);
      final firstClose = closeBox.close();
      await closeStorage.closeStarted.future;
      final secondClose = closeBox.close();
      closeStorage.blockedClose!.complete();
      await Future.wait([firstClose, secondClose]);
      expect(closeStorage.closeCalls, 1);

      final destroyStorage = _ControlledStorage(<String, dynamic>{})
        ..blockedDelete = Completer<void>();
      final destroyBox =
          await AllBox.init(destroyContainer, storage: destroyStorage);
      final firstDestroy = destroyBox.destroy();
      await destroyStorage.deleteStarted.future;
      final secondDestroy = destroyBox.destroy();
      destroyStorage.blockedDelete!.complete();
      await Future.wait([firstDestroy, secondDestroy]);
      expect(destroyStorage.deleteCalls, 1);
      expect(destroyStorage.closeCalls, 1);
    });

    test('destroy is rejected while close is in progress', () async {
      const container = 'close_conflicts';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage(<String, dynamic>{})
        ..blockedClose = Completer<void>();
      final box = await AllBox.init(container, storage: storage);

      final closing = box.close();
      await storage.closeStarted.future;

      await expectLater(box.destroy(), throwsStateError);
      storage.blockedClose!.complete();
      await closing;
    });

    test('init is rejected while close is in progress', () async {
      const container = 'init_during_close';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage(<String, dynamic>{})
        ..blockedClose = Completer<void>();
      final box = await AllBox.init(container, storage: storage);

      final closing = box.close();
      await storage.closeStarted.future;

      await expectLater(
        AllBox.init(container, storage: storage),
        throwsStateError,
      );
      storage.blockedClose!.complete();
      await closing;
    });

    test('memory rejects an incompatible pending real initialization',
        () async {
      const container = 'memory_during_pending_init';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final storage = _ControlledStorage(<String, dynamic>{})
        ..blockedLoad = Completer<Map<String, dynamic>>();

      final initializing = AllBox.init(container, storage: storage);
      await Future<void>.delayed(Duration.zero);

      await expectLater(AllBox.memory(container), throwsStateError);
      storage.blockedLoad!.complete({'backend': 'real'});
      final box = await initializing;
      expect(box.read<String>('backend'), 'real');
    });
  });

  group('storage cleanup failures', () {
    test('init failure closes storage and preserves the primary error',
        () async {
      const container = 'init_cleanup_failure';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final primary = StateError('hasPersistedData failed');
      final storage = _ControlledStorage()
        ..hasPersistedDataError = primary
        ..closeError = StateError('close failed');

      await expectLater(
        AllBox.init(container, storage: storage),
        throwsA(same(primary)),
      );
      expect(storage.closeCalls, 1);
    });

    test('close attempts storage close and preserves a flush error', () async {
      const container = 'close_cleanup_failure';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final primary = StateError('save failed');
      final storage = _ControlledStorage(<String, dynamic>{})
        ..saveError = primary
        ..closeError = StateError('close failed');
      final box = await AllBox.init(
        container,
        storage: storage,
        flushDelay: const Duration(seconds: 10),
      );
      box.write('dirty', true);

      await expectLater(box.close(), throwsA(same(primary)));
      expect(storage.closeCalls, 1);
    });

    test('destroy attempts storage close and preserves a delete error',
        () async {
      const container = 'destroy_cleanup_failure';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final primary = StateError('delete failed');
      final storage = _ControlledStorage(<String, dynamic>{})
        ..deleteError = primary
        ..closeError = StateError('close failed');
      final box = await AllBox.init(container, storage: storage);

      await expectLater(box.destroy(), throwsA(same(primary)));
      expect(storage.deleteCalls, 1);
      expect(storage.closeCalls, 1);
    });
  });
}
