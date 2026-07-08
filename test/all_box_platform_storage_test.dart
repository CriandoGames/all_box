// Tests for the automatic platform storage resolution used by AllBox.init()
// when no explicit `storage:` is supplied — see
// lib/src/core/storage/all_box_platform_storage.dart. Since this test suite
// always runs on a Dart IO platform (the VM, via `dart test`), it exercises
// the IO branch of that resolution (including the "path is required on IO"
// error) plus the explicit `storage:` override, which works identically
// regardless of platform.
//
// **PT-BR:** Testes da resolução automática de storage de plataforma usada
// pelo AllBox.init() quando nenhum `storage:` explícito é informado — veja
// lib/src/core/storage/all_box_platform_storage.dart. Como esta suíte de
// testes sempre roda em uma plataforma Dart IO (a VM, via `dart test`), ela
// exercita o ramo IO dessa resolução (incluindo o erro de "path é
// obrigatório no IO") mais o override explícito de `storage:`, que funciona
// de forma idêntica independente da plataforma.

import 'dart:io';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';
import 'package:all_box/src/core/storage/all_box_platform_storage.dart';

class _RecordingStorage implements AllBoxStorage {
  final Map<String, dynamic> _snapshot;
  bool loadCalled = false;
  bool saveCalled = false;

  _RecordingStorage([Map<String, dynamic> initial = const <String, dynamic>{}])
      : _snapshot = Map<String, dynamic>.of(initial);

  @override
  Future<bool> hasPersistedData() async => _snapshot.isNotEmpty;

  @override
  Future<Map<String, dynamic>> load() async {
    loadCalled = true;
    return Map<String, dynamic>.of(_snapshot);
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    saveCalled = true;
    _snapshot
      ..clear()
      ..addAll(snapshot);
  }

  @override
  Future<void> delete() async => _snapshot.clear();

  @override
  Future<void> close() async {}
}

void main() {
  group('AllBoxPlatformStorage.resolve on IO', () {
    test('isIOSupported is true and isWebSupported is false on the VM', () {
      expect(AllBoxPlatformStorage.isIOSupported, isTrue);
      expect(AllBoxPlatformStorage.isWebSupported, isFalse);
    });

    test('throws AllBoxStorageException when path is omitted', () {
      expect(
        () => AllBoxPlatformStorage.resolve(container: 'no_path_test'),
        throwsA(
          isA<AllBoxStorageException>().having(
            (e) => e.message,
            'message',
            contains('requires a path on IO platforms'),
          ),
        ),
      );
    });

    test('AllBox.init without path throws AllBoxStorageException', () async {
      const container = 'init_without_path_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await expectLater(
        AllBox.init(container),
        throwsA(isA<AllBoxStorageException>()),
      );
    });
  });

  group('AllBox.init(storage: ...) explicit override', () {
    test('takes priority over automatic platform resolution', () async {
      const container = 'explicit_storage_override_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final storage = _RecordingStorage({'preexisting': true});

      // No `path` at all — would normally throw on IO — but an explicit
      // `storage:` bypasses resolution entirely.
      final box = await AllBox.init(container, storage: storage);

      expect(storage.loadCalled, isTrue);
      expect(box.read<bool>('preexisting'), isTrue);

      box.write('new_key', 'new_value');
      await box.flushNow();

      expect(storage.saveCalled, isTrue);
    });
  });

  group('AllBox.init path still works exactly as before on IO', () {
    test('with an explicit path, a real directory is used', () async {
      const container = 'still_works_with_path_test';
      final dir = await Directory.systemTemp.createTemp('all_box_platform_');
      addTearDown(() async {
        AllBox.resetInstanceForTesting(container);
        if (dir.existsSync()) await dir.delete(recursive: true);
      });

      final box = await AllBox.init(container, path: dir.path);
      box.write('k', 'v');
      await box.flushNow();

      expect(File('${dir.path}/$container.db').existsSync(), isTrue);
    });
  });
}
