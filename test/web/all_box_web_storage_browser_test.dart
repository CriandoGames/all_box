// Real-browser smoke test for AllBox's Web storage: exercises the actual
// `window.localStorage`-backed path (lib/src/core/storage/platform/
// all_box_target_web.dart), not the fake used by
// test/web/all_box_web_storage_test.dart.
//
// `@TestOn('browser')` below is what makes this safe to keep inside the
// normal `test/` tree: the test runner reads that annotation up front and
// skips (never compiles) this file on any non-browser platform, so a plain
// `flutter test` — which runs on the VM — never touches the
// `dart:js_interop` import in the Web platform target. Run this file
// specifically with:
//
//   flutter test --platform chrome test/web/all_box_web_storage_browser_test.dart
//
// (equivalently, `dart test -p chrome test/web/all_box_web_storage_browser_test.dart`
// if you're driving `package:test` directly instead of through Flutter's
// tooling.)
//
// **PT-BR:** Teste de fumaça em navegador real para o storage Web do
// AllBox: exercita o caminho de fato apoiado em `window.localStorage`
// (lib/src/core/storage/platform/all_box_target_web.dart), não o fake usado
// em test/web/all_box_web_storage_test.dart.
//
// O `@TestOn('browser')` abaixo é o que torna seguro manter este arquivo
// dentro da árvore normal de `test/`: o test runner lê essa anotação antes
// de mais nada e pula (nunca compila) este arquivo em qualquer plataforma
// que não seja navegador, então um `flutter test` comum — que roda na VM —
// nunca toca no import de `dart:js_interop` do alvo de plataforma Web. Rode
// este arquivo especificamente com:
//
//   flutter test --platform chrome test/web/all_box_web_storage_browser_test.dart
//
// (equivalente a `dart test -p chrome test/web/all_box_web_storage_browser_test.dart`
// se você estiver rodando `package:test` diretamente, em vez de via
// ferramental do Flutter.)
@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';

import 'package:all_box/all_box.dart';

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
  external void removeItem(JSString key);
}

@JS('window.localStorage')
external _JSStorage get _localStorage;

String? _rawGet(String key) => _localStorage.getItem(key.toJS)?.toDart;
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

    test('a moderately large payload (5,000 keys) round-trips through '
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
  });
}
