part of '../core/all_box_impl.dart';

/// Read-only introspection over every [AllBox] container currently alive in
/// this isolate. Debug/profile-only: every method here is a no-op (returns
/// empty/`null`) in release builds, mirroring the [allBoxDebugMode] guard
/// already used by [allBoxDebugLog].
///
/// This intentionally does **not** reintroduce a listener/reactive API —
/// that was removed from `all_box` on purpose in `0.4.0` (see CHANGELOG).
/// [AllBoxInspector] never notifies anything; callers (e.g. a DevTools
/// extension) poll [snapshot] again to see fresh data instead of
/// subscribing to changes.
///
/// Existing per-container reads (`AllBox(name).getKeys()`, `.getValues()`,
/// `.read()`, `.hasData()`) already cover "I know the container name and
/// want its data" and are *not* debug-only — they are regular public API,
/// safe to call in production. What was missing, and what this class adds,
/// is *discovery* (which containers exist at all, in this isolate, right
/// now) plus metadata no existing getter exposes (storage backend, whether
/// a debounced write is still pending, an approximate on-disk size).
///
/// **PT-BR:** Introspecção somente-leitura sobre todo container [AllBox]
/// atualmente vivo neste isolate. Somente em debug/profile: todo método
/// aqui é um no-op (retorna vazio/`null`) em builds de release, espelhando
/// o guard [allBoxDebugMode] já usado por [allBoxDebugLog].
///
/// Isto propositalmente **não** reintroduz uma API de
/// listener/reatividade — isso foi removido do `all_box` de propósito na
/// `0.4.0` (veja o CHANGELOG). O [AllBoxInspector] nunca notifica nada;
/// quem chama (ex.: uma extensão do DevTools) chama [snapshot] de novo
/// para ver dados atualizados, em vez de assinar mudanças.
///
/// As leituras por container que já existiam (`AllBox(name).getKeys()`,
/// `.getValues()`, `.read()`, `.hasData()`) já cobrem "eu sei o nome do
/// container e quero seus dados" e *não* são debug-only — são API pública
/// normal, seguras de chamar em produção. O que faltava, e o que esta
/// classe adiciona, é a *descoberta* (quais containers existem, neste
/// isolate, agora) mais metadados que nenhum getter existente expunha
/// (backend de storage, se uma escrita com debounce ainda está pendente,
/// um tamanho aproximado em disco).
class AllBoxInspector {
  const AllBoxInspector._();

  /// A read-only snapshot of every container that currently has a live
  /// [AllBox] instance in this isolate — i.e. every container that has been
  /// constructed via `AllBox(name)`, `AllBox.init(...)` or
  /// `AllBox.memory(...)` at least once since the isolate started.
  ///
  /// Returns an empty list in release builds. Containers created via
  /// `AllBox(name)` but never `init`/`memory`-ed are included with
  /// [AllBoxContainerSnapshot.isInitialized] `false` and empty
  /// [AllBoxContainerSnapshot.entries].
  ///
  /// **PT-BR:** Um retrato somente-leitura de todo container que atualmente
  /// tem uma instância [AllBox] viva neste isolate — ou seja, todo
  /// container que foi construído via `AllBox(name)`, `AllBox.init(...)`
  /// ou `AllBox.memory(...)` ao menos uma vez desde que o isolate começou.
  ///
  /// Retorna uma lista vazia em builds de release. Containers criados via
  /// `AllBox(name)` mas nunca `init`/`memory`-ados entram com
  /// [AllBoxContainerSnapshot.isInitialized] `false` e [entries] vazio.
  static List<AllBoxContainerSnapshot> snapshot() {
    if (!allBoxDebugMode) return const <AllBoxContainerSnapshot>[];
    return AllBox._instances.values.map(_snapshotOf).toList(growable: false);
  }

  /// Snapshot of a single [container], or `null` if no [AllBox] instance
  /// for it has been constructed in this isolate yet, or in release
  /// builds.
  ///
  /// **PT-BR:** Retrato de um único [container], ou `null` se nenhuma
  /// instância [AllBox] para ele foi construída neste isolate ainda, ou em
  /// builds de release.
  static AllBoxContainerSnapshot? snapshotOf(String container) {
    if (!allBoxDebugMode) return null;
    final box = AllBox._instances[container];
    if (box == null) return null;
    return _snapshotOf(box);
  }

  /// Same as [snapshot], but pre-encoded to a single JSON `String`
  /// (a JSON array of objects — see [AllBoxContainerSnapshot.toJson]).
  ///
  /// This exists specifically for callers on the far side of a VM Service
  /// `eval` boundary (e.g. a DevTools extension using `EvalOnDartLibrary`):
  /// evaluating `AllBoxInspector.snapshotAsJson()` and reading the
  /// resulting `Instance.valueAsString` is far simpler than walking a
  /// `List<AllBoxContainerSnapshot>` field-by-field over the VM Service
  /// protocol. Returns `'[]'` in release builds.
  ///
  /// **PT-BR:** Igual a [snapshot], mas pré-codificado em uma única
  /// `String` JSON (um array JSON de objetos — veja
  /// [AllBoxContainerSnapshot.toJson]).
  ///
  /// Isso existe especificamente para quem chama do outro lado de uma
  /// fronteira de `eval` da VM Service (ex.: uma extensão do DevTools
  /// usando `EvalOnDartLibrary`): avaliar
  /// `AllBoxInspector.snapshotAsJson()` e ler o `Instance.valueAsString`
  /// resultante é bem mais simples do que percorrer uma
  /// `List<AllBoxContainerSnapshot>` campo a campo pelo protocolo da VM
  /// Service. Retorna `'[]'` em builds de release.
  static String snapshotAsJson() {
    if (!allBoxDebugMode) return '[]';
    return jsonEncode(snapshot().map((s) => s.toJson()).toList());
  }

  /// Same as [snapshotOf], but pre-encoded to a single JSON `String` (a
  /// JSON object — see [AllBoxContainerSnapshot.toJson]), or the JSON
  /// literal `'null'` if [container] is unknown or in release builds.
  ///
  /// **PT-BR:** Igual a [snapshotOf], mas pré-codificado em uma única
  /// `String` JSON (um objeto JSON), ou o literal JSON `'null'` se
  /// [container] for desconhecido ou em builds de release.
  static String snapshotOfAsJson(String container) {
    final snap = snapshotOf(container);
    if (snap == null) return 'null';
    return jsonEncode(snap.toJson());
  }

  static AllBoxContainerSnapshot _snapshotOf(AllBox box) {
    if (!box._initialized) {
      return AllBoxContainerSnapshot(
        container: box.container,
        isInitialized: false,
        backend: AllBoxBackendKind.unsupported,
        pendingFlush: false,
        entries: const <String, dynamic>{},
        approximateSizeBytes: 0,
      );
    }

    return AllBoxContainerSnapshot(
      container: box.container,
      isInitialized: true,
      backend: _backendOf(box._flush),
      pendingFlush: _pendingFlushOf(box._flush),
      entries: Map<String, dynamic>.unmodifiable(box._box),
      approximateSizeBytes: _approximateSizeOf(box._box),
    );
  }

  /// Classifies the storage backend behind [flush] by *name*
  /// (`runtimeType.toString()`) rather than `is AllBoxIoStorage`/
  /// `is AllBoxWebStorage` checks. This is deliberate: `AllBoxIoStorage`
  /// imports `dart:io`, which this file must not pull in — `all_box_impl`
  /// (and everything `part of` it, including this file) compiles for every
  /// platform, including Web, where `dart:io` is unavailable. Name-based
  /// classification keeps that guarantee without needing a new member on
  /// the `AllBoxStorage` interface (which would be a breaking change for
  /// callers that already implement it via the `storage:` escape hatch).
  static AllBoxBackendKind _backendOf(_FlushCoordinator? flush) {
    if (flush is _ImmediateFlushCoordinator) return AllBoxBackendKind.memory;
    if (flush is _DebouncedFlushCoordinator) {
      switch (flush._storage.runtimeType.toString()) {
        case 'AllBoxIoStorage':
          return AllBoxBackendKind.io;
        case 'AllBoxWebStorage':
          return AllBoxBackendKind.web;
        case 'AllBoxUnsupportedStorage':
          return AllBoxBackendKind.unsupported;
        default:
          return AllBoxBackendKind.custom;
      }
    }
    return AllBoxBackendKind.unsupported;
  }

  static bool _pendingFlushOf(_FlushCoordinator? flush) {
    if (flush is _DebouncedFlushCoordinator) return flush._dirty;
    return false;
  }

  static int _approximateSizeOf(Map<String, dynamic> box) {
    try {
      return utf8.encode(jsonEncode(box)).length;
    } on Object {
      // Mirrors AllBox._warnIfNotSerializable: a non-JSON-encodable value
      // must not make introspection throw. Fall back to a rough estimate
      // instead of failing.
      var total = 0;
      for (final entry in box.entries) {
        total += entry.key.length + entry.value.toString().length;
      }
      return total;
    }
  }
}
