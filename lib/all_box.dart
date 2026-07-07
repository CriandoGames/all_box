/// AllBox core: a synchronous, lightweight and fast key-value storage, with
/// crash-safe writes. Pure Dart — no Flutter dependency.
///
/// For the optional Flutter reactive layer (`AllBoxListenable`,
/// `AllBoxBuilder`), import `package:all_box/all_box_flutter.dart` instead.
///
/// Part of the `all_*` family of open-source packages
/// (alongside `all_validations_br` and `all_compress`).
///
/// **PT-BR:** Core do AllBox: um storage key-value síncrono, leve e rápido,
/// com escrita crash-safe. Dart puro — sem dependência do Flutter.
///
/// Para a camada reativa opcional do Flutter (`AllBoxListenable`,
/// `AllBoxBuilder`), importe `package:all_box/all_box_flutter.dart`.
///
/// Parte da família de pacotes open-source `all_*`
/// (junto com `all_validations_br` e `all_compress`).
library;

export 'src/core/all_box_impl.dart' show AllBox;
export 'src/core/all_box_value.dart' show AllBoxValue, AllBoxValueExtension;
