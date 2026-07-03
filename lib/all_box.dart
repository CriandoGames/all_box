/// AllBox: a synchronous, lightweight and fast key-value storage for
/// Flutter, with crash-safe writes and a pure-Flutter reactive layer.
///
/// Part of the `all_*` family of open-source packages
/// (alongside `all_validations_br` and `all_compress`).
///
/// **PT-BR:** AllBox: um storage key-value síncrono, leve e rápido para
/// Flutter, com escrita crash-safe e camada reativa 100% Flutter.
///
/// Parte da família de pacotes open-source `all_*`
/// (junto com `all_validations_br` e `all_compress`).
library;

export 'src/all_box_impl.dart' show AllBox;
export 'src/all_box_listenable.dart' show AllBoxListenable, AllBoxBuilder;
export 'src/all_box_value.dart' show AllBoxValue, AllBoxValueExtension;
