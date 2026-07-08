// Tests for AllBoxWebStorage: the pure-Dart logic (JSON encode/decode, key
// naming, error wrapping) behind AllBox's Web backend. This class has zero
// platform-specific imports (no dart:js_interop, no dart:html), so it is
// tested here directly with a fake AllBoxBrowserStorage — no browser
// required.
//
// The real, window.localStorage-backed AllBoxBrowserStorage lives behind a
// conditional import in lib/src/core/storage/platform/all_box_target_web.dart
// and is only ever compiled/constructed on Web; it isn't (and can't easily
// be) exercised by a normal VM test run. If a real-browser smoke test is
// ever added for it, it would run via:
//
//   dart test -p chrome test/web/all_box_web_storage_test.dart
//
// **PT-BR:** Testes do AllBoxWebStorage: a lógica pura em Dart (codificação/
// decodificação JSON, nomeação de chave, encapsulamento de erros) por trás
// do backend Web do AllBox. Esta classe não tem nenhum import específico de
// plataforma (sem dart:js_interop, sem dart:html), então é testada aqui
// diretamente com um AllBoxBrowserStorage falso — sem precisar de
// navegador.
//
// A implementação real, apoiada em window.localStorage, vive atrás de um
// import condicional em
// lib/src/core/storage/platform/all_box_target_web.dart e só é de fato
// compilada/construída na Web; não é (e não seria fácil de) exercitada por
// uma execução normal de teste na VM. Se um teste de fumaça em navegador
// real for adicionado para ela algum dia, rodaria via:
//
//   dart test -p chrome test/web/all_box_web_storage_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:all_box/src/core/storage/all_box_storage.dart';
import 'package:all_box/src/core/storage/all_box_storage_exception.dart';
import 'package:all_box/src/core/storage/all_box_web_storage.dart';

class _FakeBrowserStorage implements AllBoxBrowserStorage {
  final Map<String, String> _map = <String, String>{};

  Object Function()? getError;
  Object Function()? setError;
  Object Function()? removeError;

  @override
  String? getItem(String key) {
    final error = getError;
    if (error != null) throw error();
    return _map[key];
  }

  @override
  void setItem(String key, String value) {
    final error = setError;
    if (error != null) throw error();
    _map[key] = value;
  }

  @override
  void removeItem(String key) {
    final error = removeError;
    if (error != null) throw error();
    _map.remove(key);
  }
}

void main() {
  group('AllBoxWebStorage', () {
    test('storageKey namespaces by container', () {
      final storage = AllBoxWebStorage(
        container: 'settings',
        browserStorage: _FakeBrowserStorage(),
      );
      expect(storage.storageKey, 'all_box::settings');
    });

    test('hasPersistedData is false before any save, true after', () async {
      final browser = _FakeBrowserStorage();
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      expect(await storage.hasPersistedData(), isFalse);

      await storage.save({'a': 1}, mode: AllBoxPersistMode.flush);

      expect(await storage.hasPersistedData(), isTrue);
    });

    test('load returns {} when the key is absent', () async {
      final storage = AllBoxWebStorage(
        container: 'c',
        browserStorage: _FakeBrowserStorage(),
      );
      expect(await storage.load(), isEmpty);
    });

    test('save then load round-trips the snapshot', () async {
      final browser = _FakeBrowserStorage();
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await storage.save(
        {'darkMode': true, 'name': 'Carlos'},
        mode: AllBoxPersistMode.save,
      );

      final loaded = await storage.load();
      expect(loaded, {'darkMode': true, 'name': 'Carlos'});
    });

    test('save and flush modes are both accepted and round-trip the same '
        'way (no meaningful distinction on Web)', () async {
      final browser = _FakeBrowserStorage();
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await storage.save({'k': 1}, mode: AllBoxPersistMode.save);
      expect((await storage.load())['k'], 1);

      await storage.save({'k': 2}, mode: AllBoxPersistMode.flush);
      expect((await storage.load())['k'], 2);
    });

    test('load never throws on invalid JSON — falls back to {}', () async {
      final browser = _FakeBrowserStorage();
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      browser.setItem(storage.storageKey, '{ not valid json ][');

      expect(await storage.load(), isEmpty);
    });

    test('load never throws when the browser storage itself throws',
        () async {
      final browser = _FakeBrowserStorage()
        ..getError = () => StateError('storage unavailable');
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      expect(await storage.load(), isEmpty);
    });

    test('save throws AllBoxStorageException when the value is not '
        'JSON-encodable', () async {
      final storage = AllBoxWebStorage(
        container: 'c',
        browserStorage: _FakeBrowserStorage(),
      );

      await expectLater(
        storage.save({'when': DateTime.now()}, mode: AllBoxPersistMode.flush),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('save throws a quota-flavored AllBoxStorageException when the '
        'browser storage rejects the write with a quota-like error',
        () async {
      final browser = _FakeBrowserStorage()
        ..setError = () => Exception('QuotaExceededError: too much data');
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await expectLater(
        storage.save({'a': 1}, mode: AllBoxPersistMode.flush),
        throwsA(
          isA<AllBoxStorageException>().having(
            (e) => e.message,
            'message',
            contains('quota'),
          ),
        ),
      );
    });

    test('save throws a generic AllBoxStorageException for other browser '
        'storage failures', () async {
      final browser = _FakeBrowserStorage()
        ..setError = () => StateError('disabled by user');
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await expectLater(
        storage.save({'a': 1}, mode: AllBoxPersistMode.flush),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('delete removes the key', () async {
      final browser = _FakeBrowserStorage();
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await storage.save({'a': 1}, mode: AllBoxPersistMode.flush);
      expect(await storage.hasPersistedData(), isTrue);

      await storage.delete();
      expect(await storage.hasPersistedData(), isFalse);
    });

    test('delete throws AllBoxStorageException when the browser storage '
        'throws', () async {
      final browser = _FakeBrowserStorage()
        ..removeError = () => StateError('boom');
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await expectLater(
        storage.delete(),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('hasPersistedData throws AllBoxStorageException when the browser '
        'storage throws', () async {
      final browser = _FakeBrowserStorage()
        ..getError = () => StateError('boom');
      final storage = AllBoxWebStorage(container: 'c', browserStorage: browser);

      await expectLater(
        storage.hasPersistedData(),
        throwsA(isA<AllBoxStorageException>()),
      );
    });

    test('close() is a no-op that completes normally', () async {
      final storage = AllBoxWebStorage(
        container: 'c',
        browserStorage: _FakeBrowserStorage(),
      );
      await expectLater(storage.close(), completes);
    });
  });
}
