import 'all_box_storage.dart';
import 'platform/all_box_target.dart' as target;

/// Resolves the [AllBoxStorage] `AllBox.init()` should use when no explicit
/// `storage:` argument was supplied, based on the current compile target:
///
/// - **Web** (`dart.library.js_interop`): always uses `window.localStorage`
///   via [target.createPlatformStorage]. `path`, if supplied, is silently
///   ignored — passing it should never be an error, since callers that
///   share `init()` code across IO and Web shouldn't have to special-case
///   Web just because they always pass `path`.
/// - **IO** (`dart.library.io`): uses a real `<container>.db` file under
///   `path`. `path` is required here — see the [AllBoxStorageException]
///   thrown by the IO target when it's missing.
/// - **Anything else**: throws via [AllBoxUnsupportedStorage].
///
/// **PT-BR:** Resolve o [AllBoxStorage] que o `AllBox.init()` deve usar
/// quando nenhum argumento `storage:` explícito foi passado, com base no
/// alvo de compilação atual:
///
/// - **Web** (`dart.library.js_interop`): sempre usa o
///   `window.localStorage` via [target.createPlatformStorage]. `path`, se
///   informado, é silenciosamente ignorado — passá-lo nunca deveria ser um
///   erro, já que quem compartilha código de `init()` entre IO e Web não
///   deveria precisar tratar a Web como caso especial só por sempre passar
///   `path`.
/// - **IO** (`dart.library.io`): usa um arquivo `<container>.db` real sob
///   `path`. `path` é obrigatório aqui — veja a `AllBoxStorageException`
///   lançada pelo alvo IO quando ele está ausente.
/// - **Qualquer outra coisa**: lança via `AllBoxUnsupportedStorage`.
class AllBoxPlatformStorage {
  const AllBoxPlatformStorage._();

  /// Whether the current compile target is a Dart IO platform (native VM,
  /// AOT, Flutter mobile/desktop).
  ///
  /// **PT-BR:** Se o alvo de compilação atual é uma plataforma Dart IO (VM
  /// nativa, AOT, Flutter mobile/desktop).
  static bool get isIOSupported => target.isIOSupported;

  /// Whether the current compile target is Web (`dart2js`, `dartdevc`,
  /// `dart2wasm` with JS interop).
  ///
  /// **PT-BR:** Se o alvo de compilação atual é Web (`dart2js`, `dartdevc`,
  /// `dart2wasm` com JS interop).
  static bool get isWebSupported => target.isWebSupported;

  /// Resolves the [AllBoxStorage] to use for [container], given the `path`
  /// (if any) passed to `AllBox.init`.
  ///
  /// **PT-BR:** Resolve o [AllBoxStorage] a usar para [container], dado o
  /// `path` (se houver) passado para `AllBox.init`.
  static AllBoxStorage resolve({
    required String container,
    String? path,
    bool validateContainerName = false,
  }) {
    return target.createPlatformStorage(
      container: container,
      path: path,
      validateContainerName: validateContainerName,
    );
  }
}
