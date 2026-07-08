import '../all_box_io_storage.dart';
import '../all_box_storage.dart';
import '../all_box_storage_exception.dart';

/// IO target: selected via the `dart.library.io` conditional import
/// condition. Backs `AllBox` with a real `<container>.db` file.
///
/// **PT-BR:** Alvo IO: selecionado via a condição de import condicional
/// `dart.library.io`. Sustenta o `AllBox` com um arquivo `<container>.db`
/// real.
const bool isIOSupported = true;
const bool isWebSupported = false;

AllBoxStorage createPlatformStorage({
  required String container,
  String? path,
}) {
  if (path == null) {
    throw AllBoxStorageException(
      'AllBox requires a path on IO platforms. On Web, path is not '
      'required. In Flutter apps, pass a directory path from your app '
      'layer.',
    );
  }
  return AllBoxIoStorage(container: container, directoryPath: path);
}
