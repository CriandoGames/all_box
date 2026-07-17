// Real-browser smoke test for AllBox's Web storage: exercises the actual
// `window.localStorage`-backed path (lib/src/core/storage/platform/
// all_box_target_web.dart), not the fake used by
// test/web/all_box_web_storage_test.dart.
//
// `@TestOn('browser')` below is what makes this safe to keep inside the
// normal `test/` tree: the test runner reads that annotation up front and
// skips (never compiles) this file on any non-browser platform, so a plain
// `dart test` — which runs on the VM — never touches the `dart:js_interop`
// import in the Web platform target. Run this file specifically with:
//
//   dart test -p chrome test/web/all_box_web_storage_browser_test.dart
//
// **PT-BR:** Teste de fumaça em navegador real para o storage Web do
// AllBox: exercita o caminho de fato apoiado em `window.localStorage`
// (lib/src/core/storage/platform/all_box_target_web.dart), não o fake usado
// em test/web/all_box_web_storage_test.dart.
//
// O `@TestOn('browser')` abaixo é o que torna seguro manter este arquivo
// dentro da árvore normal de `test/`: o test runner lê essa anotação antes
// de mais nada e pula (nunca compila) este arquivo em qualquer plataforma
// que não seja navegador, então um `dart test` comum — que roda na VM —
// nunca toca no import de `dart:js_interop` do alvo de plataforma Web. Rode
// este arquivo especificamente com:
//
//   dart test -p chrome test/web/all_box_web_storage_browser_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';
import 'package:all_box/src/core/storage/platform/all_box_indexed_db_browser.dart';

/// Minimal static-interop view over `window.localStorage`, declared locally
/// (not imported from the package) so this test can assert against the
/// *real* browser storage independently of AllBox's own implementation —
/// if AllBox's internal wiring to `window.localStorage` were ever broken,
/// this still reads/writes the real thing directly.
///
/// **PT-BR:** Visão mínima de static interop sobre o `window.localStorage`,
/// declarada localmente (não importada do pacote), para que este teste
/// possa verificar o storage *real* do navegador de forma independente da
/// implementação do próprio AllBox — se a conexão interna do AllBox com o
/// `window.localStorage` algum dia quebrar, isto ainda lê/escreve o
/// navegador de verdade diretamente.
extension type _JSStorage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

@JS('window.localStorage')
external _JSStorage get _localStorage;

String? _rawGet(String key) => _localStorage.getItem(key.toJS)?.toDart;
void _rawSet(String key, String value) =>
    _localStorage.setItem(key.toJS, value.toJS);
void _rawRemove(String key) => _localStorage.removeItem(key.toJS);

void main() {
  group('AllBox Web storage (real browser)', () {
    test('AllBox.init(container) with no path uses window.localStorage',
        () async {
      const container = 'browser_smoke_test';
      addTearDown(() {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
      });
      _rawRemove('all_box::$container');

      final box = await AllBox.init(container);
      box.write('theme', 'dark');
      await box.writeAndFlush('name', 'Carlos');

      // Assert against the real window.localStorage, not just AllBox's own
      // in-memory view — this is what proves the wiring actually reaches
      // the browser.
      final raw = _rawGet('all_box::$container');
      expect(raw, isNotNull);
      expect(raw, contains('"theme":"dark"'));
      expect(raw, contains('"name":"Carlos"'));
    });

    test('data persists across a fresh AllBox.init() (simulated reload)',
        () async {
      const container = 'browser_persist_test';
      addTearDown(() {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
      });
      _rawRemove('all_box::$container');

      final first = await AllBox.init(container);
      await first.writeAndFlush('counter', 42);

      // Simulate a page reload: drop the in-memory singleton, but the data
      // stays in window.localStorage (real browser storage isn't wiped by
      // this).
      AllBox.resetInstanceForTesting(container);

      final second = await AllBox.init(container);
      expect(second.read<int>('counter'), 42);
    });

    test('erase() removes the container from window.localStorage', () async {
      const container = 'browser_erase_test';
      addTearDown(() {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
      });
      _rawRemove('all_box::$container');

      final box = await AllBox.init(container);
      await box.writeAndFlush('k', 'v');
      expect(_rawGet('all_box::$container'), isNotNull);

      box.erase();
      await box.flushNow();

      final raw = _rawGet('all_box::$container');
      expect(raw, anyOf(isNull, '{}'));
    });

    test(
        'a moderately large payload (5,000 keys) round-trips through '
        'real localStorage', () async {
      const container = 'browser_large_payload_test';
      addTearDown(() {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
      });
      _rawRemove('all_box::$container');

      final box = await AllBox.init(container);
      for (var i = 0; i < 5000; i++) {
        box.write('key_$i', 'value_$i');
      }
      await box.flushNow();

      AllBox.resetInstanceForTesting(container);
      final reloaded = await AllBox.init(container);

      expect(reloaded.getKeys().length, 5000);
      expect(reloaded.read<String>('key_0'), 'value_0');
      expect(reloaded.read<String>('key_4999'), 'value_4999');
    });

    test('path is silently ignored on Web — init still uses localStorage',
        () async {
      const container = 'browser_ignored_path_test';
      addTearDown(() {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
      });
      _rawRemove('all_box::$container');

      // A path that obviously can't exist on Web — must be ignored, not
      // thrown.
      final box = await AllBox.init(container, path: '/not/a/real/path');
      await box.writeAndFlush('k', 'v');

      expect(_rawGet('all_box::$container'), isNotNull);
    });

    test('IndexedDB beta backend is off by default', () async {
      const container = 'browser_indexed_db_default_off_test';
      addTearDown(() async {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
        await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      });
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      _rawRemove('all_box::$container');

      final box = await AllBox.init(container);
      await box.writeAndFlush('k', 'v');

      final snap = AllBoxInspector.snapshotOf(container)!;
      expect(snap.backend, AllBoxBackendKind.web);
      expect(snap.backendDetail, 'localStorage');
      expect(_rawGet('all_box::$container'), contains('"k":"v"'));
    });

    test(
        'experimental IndexedDB opt-in routes AllBox.init through migration '
        'storage', () async {
      const container = 'browser_experimental_indexed_db_test';
      addTearDown(() async {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
        await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      });
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      _rawRemove('all_box::$container');

      _rawSet('all_box::$container', '{"legacy":true}');

      final box = await AllBox.init(
        container,
        experimentalIndexedDbBackend: true,
      );
      expect(box.read<bool>('legacy'), isTrue);
      expect(_rawGet('all_box::$container'), isNull);

      final snap = AllBoxInspector.snapshotOf(container)!;
      expect(snap.backend, AllBoxBackendKind.web);
      expect(snap.backendDetail, 'indexedDBMigration');

      await box.writeAndFlush('fresh', 'indexed');
      await box.close();

      final reloaded = await AllBox.init(
        container,
        experimentalIndexedDbBackend: true,
      );
      expect(reloaded.read<bool>('legacy'), isTrue);
      expect(reloaded.read<String>('fresh'), 'indexed');
      expect(_rawGet('all_box::$container'), isNull);

      await reloaded.close();
    });

    test('disabling IndexedDB opt-in returns AllBox.init to localStorage',
        () async {
      const container = 'browser_experimental_disable_test';
      addTearDown(() async {
        AllBox.resetInstanceForTesting(container);
        _rawRemove('all_box::$container');
        await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      });
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      _rawRemove('all_box::$container');

      final indexed = await AllBox.init(
        container,
        experimentalIndexedDbBackend: true,
      );
      await indexed.writeAndFlush('stored', 'indexed');
      await indexed.close();
      expect(_rawGet('all_box::$container'), isNull);

      final local = await AllBox.init(container);
      expect(local.read<String>('stored'), isNull);
      final localSnap = AllBoxInspector.snapshotOf(container)!;
      expect(localSnap.backend, AllBoxBackendKind.web);
      expect(localSnap.backendDetail, 'localStorage');

      await local.writeAndFlush('stored', 'local');
      expect(_rawGet('all_box::$container'), contains('"stored":"local"'));
      await local.close();

      final indexedReloaded = await AllBox.init(
        container,
        experimentalIndexedDbBackend: true,
      );
      expect(indexedReloaded.read<String>('stored'), 'indexed');
      expect(_rawGet('all_box::$container'), contains('"stored":"local"'));
      await indexedReloaded.close();
    });

    test('experimental IndexedDB opt-in keeps containers isolated', () async {
      const firstContainer = 'browser_experimental_first_container';
      const secondContainer = 'browser_experimental_second_container';
      addTearDown(() async {
        AllBox.resetInstanceForTesting(firstContainer);
        AllBox.resetInstanceForTesting(secondContainer);
        _rawRemove('all_box::$firstContainer');
        _rawRemove('all_box::$secondContainer');
        await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      });
      await AllBoxBrowserIndexedDbDriver.deleteDatabaseForTesting('all_box');
      _rawRemove('all_box::$firstContainer');
      _rawRemove('all_box::$secondContainer');

      _rawSet('all_box::$firstContainer', '{"name":"first-legacy"}');
      _rawSet('all_box::$secondContainer', '{"name":"second-legacy"}');

      final first = await AllBox.init(
        firstContainer,
        experimentalIndexedDbBackend: true,
      );
      final second = await AllBox.init(
        secondContainer,
        experimentalIndexedDbBackend: true,
      );

      expect(first.read<String>('name'), 'first-legacy');
      expect(second.read<String>('name'), 'second-legacy');
      expect(_rawGet('all_box::$firstContainer'), isNull);
      expect(_rawGet('all_box::$secondContainer'), isNull);

      await first.writeAndFlush('fresh', 'first-indexed');
      await second.writeAndFlush('fresh', 'second-indexed');
      await first.close();
      await second.close();

      final firstReloaded = await AllBox.init(
        firstContainer,
        experimentalIndexedDbBackend: true,
      );
      final secondReloaded = await AllBox.init(
        secondContainer,
        experimentalIndexedDbBackend: true,
      );

      expect(firstReloaded.read<String>('name'), 'first-legacy');
      expect(firstReloaded.read<String>('fresh'), 'first-indexed');
      expect(secondReloaded.read<String>('name'), 'second-legacy');
      expect(secondReloaded.read<String>('fresh'), 'second-indexed');

      await firstReloaded.close();
      await secondReloaded.close();
    });
  });
}
