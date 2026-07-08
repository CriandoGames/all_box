import 'dart:convert';

import 'all_box_storage.dart';
import 'all_box_storage_exception.dart';

/// The minimal, synchronous key-value surface `AllBoxWebStorage` needs from
/// a browser storage object. Matches the shape of `Storage`
/// (`window.localStorage`) on purpose, but is declared here in plain Dart
/// (no `dart:js_interop`, no `dart:html`) so it can be faked in plain VM
/// tests without a browser.
///
/// The real implementation (backed by `window.localStorage` via
/// `dart:js_interop`) lives behind a conditional import and is only ever
/// constructed on Web — see `lib/src/core/storage/platform/`.
///
/// **PT-BR:** A superfície mínima e síncrona de chave-valor que o
/// `AllBoxWebStorage` precisa de um objeto de storage do navegador. Casa de
/// propósito com o formato do `Storage` (`window.localStorage`), mas é
/// declarada aqui em Dart puro (sem `dart:js_interop`, sem `dart:html`)
/// para poder ser simulada em testes de VM comuns, sem navegador.
///
/// A implementação real (apoiada em `window.localStorage` via
/// `dart:js_interop`) vive atrás de um import condicional e só é
/// construída de fato na Web — veja `lib/src/core/storage/platform/`.
abstract interface class AllBoxBrowserStorage {
  /// Returns the current value for [key], or `null` if it isn't set.
  ///
  /// **PT-BR:** Retorna o valor atual de [key], ou `null` se não estiver
  /// definido.
  String? getItem(String key);

  /// Sets [key] to [value], overwriting any previous value.
  ///
  /// **PT-BR:** Define [key] como [value], sobrescrevendo qualquer valor
  /// anterior.
  void setItem(String key, String value);

  /// Removes [key], if present.
  ///
  /// **PT-BR:** Remove [key], se presente.
  void removeItem(String key);
}

/// Web-friendly [AllBoxStorage]: persists the entire container snapshot as a
/// single JSON string under one browser-storage key (`all_box::<container>`,
/// via [AllBoxBrowserStorage]).
///
/// This class itself has **zero** platform-specific imports — no
/// `dart:js_interop`, no `dart:html` — which is what makes it directly
/// testable with a plain `dart test` and a fake [AllBoxBrowserStorage], no
/// browser required. The real, `window.localStorage`-backed
/// [AllBoxBrowserStorage] is only wired in by the platform resolver when
/// actually compiling for Web.
///
/// `load()` never throws: a missing key, invalid JSON, or a failure to even
/// read from storage all result in an empty map. `hasPersistedData()`,
/// `save()` and `delete()` do throw — as [AllBoxStorageException] — since
/// those are operations the caller (`AllBox.init`/`write`) needs to know
/// about (e.g. a quota-exceeded error while saving).
///
/// **PT-BR:** [AllBoxStorage] amigável para Web: persiste o snapshot inteiro
/// do container como uma única string JSON sob uma chave do storage do
/// navegador (`all_box::<container>`, via [AllBoxBrowserStorage]).
///
/// Esta classe em si não tem **nenhum** import específico de plataforma —
/// nem `dart:js_interop`, nem `dart:html` — o que é o que a torna
/// diretamente testável com um `dart test` comum e um [AllBoxBrowserStorage]
/// falso, sem precisar de navegador. O [AllBoxBrowserStorage] real, apoiado
/// em `window.localStorage`, só é conectado pelo resolvedor de plataforma
/// quando de fato compilando para Web.
///
/// `load()` nunca lança exceção: uma chave ausente, JSON inválido, ou uma
/// falha até para ler do storage resultam em um map vazio. `hasPersistedData()`,
/// `save()` e `delete()` lançam sim — como [AllBoxStorageException] — já
/// que são operações sobre as quais quem chama (`AllBox.init`/`write`)
/// precisa saber (ex.: um erro de quota excedida ao salvar).
class AllBoxWebStorage implements AllBoxStorage {
  AllBoxWebStorage({
    required this.container,
    required AllBoxBrowserStorage browserStorage,
  }) : _storage = browserStorage;

  final String container;
  final AllBoxBrowserStorage _storage;

  /// The single browser-storage key used for this entire container.
  ///
  /// **PT-BR:** A única chave do storage do navegador usada para este
  /// container inteiro.
  String get storageKey => 'all_box::$container';

  @override
  Future<bool> hasPersistedData() async {
    try {
      return _storage.getItem(storageKey) != null;
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to check for existing Web storage '
        'data. The browser storage may be unavailable (e.g. disabled by '
        'the user, or in a restricted iframe).',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<Map<String, dynamic>> load() async {
    String? raw;
    try {
      raw = _storage.getItem(storageKey);
    } on Object {
      // Never throw from load(): an unreadable storage just starts empty.
      return <String, dynamic>{};
    }

    if (raw == null) return <String, dynamic>{};

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map<dynamic, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return <String, dynamic>{};
    } on FormatException {
      return <String, dynamic>{};
    }
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    // Web storage has no meaningful distinction between `save` and `flush`
    // (there's no OS page cache to force through, no fsync): both are
    // treated identically, as an immediate, synchronous localStorage write.
    final String jsonText;
    try {
      jsonText = jsonEncode(snapshot);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to encode snapshot to JSON for Web '
        'storage.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    try {
      _storage.setItem(storageKey, jsonText);
    } on Object catch (error, stackTrace) {
      final message = _looksLikeQuotaError(error)
          ? 'AllBox("$container"): browser storage quota exceeded while '
              'saving. Web storage (localStorage) has a limited, '
              'browser-dependent size budget shared by everything stored '
              'under the current origin — consider storing less data, or '
              'not using AllBox for large payloads on Web.'
          : 'AllBox("$container"): failed to write to Web storage. It may '
              'be unavailable (e.g. disabled by the user, private/'
              'incognito mode in some browsers, or a restricted iframe).';
      throw AllBoxStorageException(
        message,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> delete() async {
    try {
      _storage.removeItem(storageKey);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to delete Web storage data.',
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<void> close() async {}

  bool _looksLikeQuotaError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('quota') || text.contains('exceeded');
  }
}
