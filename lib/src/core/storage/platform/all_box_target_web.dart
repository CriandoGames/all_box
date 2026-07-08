import 'dart:js_interop';

import '../all_box_storage.dart';
import '../all_box_web_storage.dart';

/// Web target: selected via the `dart.library.js_interop` conditional
/// import condition. Backs `AllBox` with `window.localStorage`, accessed
/// through pure `dart:js_interop` static interop — deliberately **not**
/// `dart:html` (which blocks `dart2wasm` compilation) and **not**
/// `package:web` (an extra dependency this package doesn't need: the two
/// or three `Storage` methods used here are trivial to declare directly).
///
/// `path` is intentionally accepted and ignored here: code that shares
/// `AllBox.init(container, path: ...)` across IO and Web targets shouldn't
/// have to special-case Web just because it always passes `path`.
///
/// **PT-BR:** Alvo Web: selecionado via a condição de import condicional
/// `dart.library.js_interop`. Sustenta o `AllBox` com `window.localStorage`,
/// acessado através de static interop puro do `dart:js_interop` —
/// deliberadamente **sem** `dart:html` (que bloqueia a compilação para
/// `dart2wasm`) e **sem** `package:web` (uma dependência extra que este
/// pacote não precisa: os dois ou três métodos de `Storage` usados aqui são
/// triviais de declarar diretamente).
///
/// `path` é intencionalmente aceito e ignorado aqui: código que compartilha
/// `AllBox.init(container, path: ...)` entre alvos IO e Web não deveria
/// precisar tratar a Web como caso especial só porque sempre passa `path`.
const bool isIOSupported = false;
const bool isWebSupported = true;

/// Static-interop view over the `Storage` interface (the same interface
/// `window.localStorage` and `window.sessionStorage` implement), exposing
/// only the three synchronous methods `AllBoxWebStorage` needs.
///
/// **PT-BR:** Visão de static interop sobre a interface `Storage` (a mesma
/// interface que `window.localStorage` e `window.sessionStorage`
/// implementam), expondo apenas os três métodos síncronos que o
/// `AllBoxWebStorage` precisa.
extension type _JSStorage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void setItem(JSString key, JSString value);
  external void removeItem(JSString key);
}

@JS('window.localStorage')
external _JSStorage get _jsLocalStorage;

class _LocalStorageBrowserStorage implements AllBoxBrowserStorage {
  const _LocalStorageBrowserStorage();

  @override
  String? getItem(String key) => _jsLocalStorage.getItem(key.toJS)?.toDart;

  @override
  void setItem(String key, String value) =>
      _jsLocalStorage.setItem(key.toJS, value.toJS);

  @override
  void removeItem(String key) => _jsLocalStorage.removeItem(key.toJS);
}

AllBoxStorage createPlatformStorage({
  required String container,
  String? path,
}) {
  return AllBoxWebStorage(
    container: container,
    browserStorage: const _LocalStorageBrowserStorage(),
  );
}
