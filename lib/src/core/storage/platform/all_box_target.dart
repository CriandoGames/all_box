/// Selects, at compile time, which platform target backs [createPlatformStorage]
/// (and the [isIOSupported]/[isWebSupported] flags): [dart.library.io] on
/// native/VM targets, [dart.library.js_interop] on Web targets (`dart2js`,
/// `dartdevc`, `dart2wasm`), or the unsupported stub otherwise.
///
/// This is the only place in the package that decides "am I IO or Web?" —
/// deliberately not `dart:io`'s `Platform` (unavailable on Web) nor
/// Flutter's `kIsWeb` (this is the pure-Dart core; it cannot depend on
/// Flutter).
///
/// **PT-BR:** Seleciona, em tempo de compilação, qual alvo de plataforma
/// sustenta o [createPlatformStorage] (e as flags [isIOSupported]/
/// [isWebSupported]): [dart.library.io] em alvos nativos/VM,
/// [dart.library.js_interop] em alvos Web (`dart2js`, `dartdevc`,
/// `dart2wasm`), ou o stub de não suportado, caso contrário.
///
/// Este é o único lugar do pacote que decide "eu sou IO ou Web?" —
/// deliberadamente não o `Platform` do `dart:io` (indisponível na Web) nem
/// o `kIsWeb` do Flutter (este é o core em Dart puro; não pode depender do
/// Flutter).
library;

export 'all_box_target_stub.dart'
    if (dart.library.io) 'all_box_target_io.dart'
    if (dart.library.js_interop) 'all_box_target_web.dart';
