import 'all_box_storage.dart';
import 'all_box_storage_exception.dart';

/// [AllBoxStorage] used when `AllBox` cannot determine a suitable storage
/// backend for the current compile target (neither `dart:io` nor
/// `dart.library.js_interop` is available — e.g. some standalone WASM
/// targets without JS interop). Every operation throws a clear
/// [AllBoxStorageException] instead of failing in some more confusing way.
///
/// **PT-BR:** [AllBoxStorage] usado quando o `AllBox` não consegue
/// determinar um backend de storage adequado para o alvo de compilação
/// atual (nem `dart:io` nem `dart.library.js_interop` disponíveis — ex.:
/// alguns alvos WASM standalone sem JS interop). Toda operação lança uma
/// [AllBoxStorageException] clara, em vez de falhar de um jeito mais
/// confuso.
class AllBoxUnsupportedStorage implements AllBoxStorage {
  const AllBoxUnsupportedStorage();

  Never _unsupported() {
    throw AllBoxStorageException(
      'AllBox has no built-in storage for the current platform (neither '
      'IO nor Web were detected). Pass an explicit `storage:` argument to '
      'AllBox.init() with your own AllBoxStorage implementation for this '
      'target.',
    );
  }

  @override
  Future<bool> hasPersistedData() async => _unsupported();

  @override
  Future<Map<String, dynamic>> load() async => _unsupported();

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async =>
      _unsupported();

  @override
  Future<void> delete() async => _unsupported();

  @override
  Future<void> close() async {}
}
