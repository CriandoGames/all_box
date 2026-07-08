/// AllBox: a synchronous, lightweight and fast key-value storage, with
/// crash-safe writes. Pure Dart, with no reactive layer — `write()`,
/// `remove()` and `erase()` only update memory and schedule persistence;
/// they never notify anything.
///
/// Part of the `all_*` family of open-source packages
/// (alongside `all_validations_br` and `all_compress`).
///
/// **PT-BR:** AllBox: um storage key-value síncrono, leve e rápido, com
/// escrita crash-safe. Dart puro, sem camada reativa — `write()`,
/// `remove()` e `erase()` só atualizam a memória e agendam a persistência;
/// nunca notificam nada.
///
/// Parte da família de pacotes open-source `all_*`
/// (junto com `all_validations_br` e `all_compress`).
library;

export 'src/core/all_box_impl.dart'
    show AllBox, AllBoxStorage, AllBoxPersistMode, AllBoxStorageException;
