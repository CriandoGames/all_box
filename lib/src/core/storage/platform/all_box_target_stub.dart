import '../all_box_storage.dart';
import '../all_box_unsupported_storage.dart';

/// Default (fallback) target: used only when neither `dart:io` nor
/// `dart.library.js_interop` is available for the current compile target.
///
/// **PT-BR:** Alvo padrão (fallback): usado apenas quando nem `dart:io` nem
/// `dart.library.js_interop` estão disponíveis para o alvo de compilação
/// atual.
const bool isIOSupported = false;
const bool isWebSupported = false;

AllBoxStorage createPlatformStorage({
  required String container,
  String? path,
}) {
  return const AllBoxUnsupportedStorage();
}
