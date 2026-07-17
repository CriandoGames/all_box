part of '../core/all_box_impl.dart';

/// Which concrete storage backend a container is currently persisted with.
///
/// Determined without importing platform-specific storage classes into this
/// file (that would drag `dart:io` into every compile target) — see
/// [AllBoxInspector] for how this is derived.
///
/// **PT-BR:** Qual backend de storage concreto um container está usando no
/// momento.
enum AllBoxBackendKind {
  /// Disk-backed (`AllBoxIoStorage`): native VM/AOT, Flutter mobile/desktop.
  ///
  /// **PT-BR:** Baseado em disco: VM/AOT nativa, Flutter mobile/desktop.
  io,

  /// Browser-backed (`AllBoxWebStorage`, `window.localStorage`).
  ///
  /// **PT-BR:** Baseado no navegador (`window.localStorage`).
  web,

  /// Pure in-memory backend used by [AllBox.memory] (tests).
  ///
  /// **PT-BR:** Backend puramente em memória, usado por [AllBox.memory]
  /// (testes).
  memory,

  /// No suitable backend for the current compile target
  /// (`AllBoxUnsupportedStorage`), or the container has never been
  /// initialized.
  ///
  /// **PT-BR:** Nenhum backend adequado para o alvo de compilação atual, ou
  /// o container nunca foi inicializado.
  unsupported,

  /// A caller-supplied `storage:` implementation that isn't one of the
  /// backends this package ships.
  ///
  /// **PT-BR:** Uma implementação de `storage:` fornecida por quem chama,
  /// que não é um dos backends que este pacote oferece.
  custom,
}

/// Read-only, point-in-time snapshot of one [AllBox] container's state,
/// produced by [AllBoxInspector]. Debug/profile-only — see
/// [AllBoxInspector.snapshot].
///
/// **PT-BR:** Retrato somente-leitura, de um instante no tempo, do estado de
/// um container [AllBox], produzido por [AllBoxInspector]. Somente em
/// debug/profile — veja [AllBoxInspector.snapshot].
class AllBoxContainerSnapshot {
  /// Creates a read-only snapshot of one container.
  const AllBoxContainerSnapshot({
    required this.container,
    required this.isInitialized,
    required this.backend,
    required this.pendingFlush,
    required this.entries,
    required this.approximateSizeBytes,
  });

  /// The container's logical name — same value as [AllBox.container].
  ///
  /// **PT-BR:** O nome lógico do container — mesmo valor de
  /// [AllBox.container].
  final String container;

  /// Whether `init()`/`memory()` has completed for this container. `false`
  /// means this is only a placeholder instance (created by `AllBox(name)`
  /// but never initialized) — [entries] is empty and [backend] is
  /// [AllBoxBackendKind.unsupported] in that case.
  ///
  /// **PT-BR:** Se `init()`/`memory()` já terminou para este container.
  /// `false` significa que é só uma instância placeholder (criada por
  /// `AllBox(name)` mas nunca inicializada) — [entries] fica vazio e
  /// [backend] é [AllBoxBackendKind.unsupported] nesse caso.
  final bool isInitialized;

  /// Which storage backend this container is persisted with.
  ///
  /// **PT-BR:** Com qual backend de storage este container é persistido.
  final AllBoxBackendKind backend;

  /// Whether there is a debounced write waiting to be flushed to storage
  /// (i.e. memory and disk/browser storage may currently disagree).
  /// Always `false` for [AllBoxBackendKind.memory], which has no debounce
  /// window.
  ///
  /// **PT-BR:** Se há uma escrita com debounce aguardando para ser
  /// persistida (ou seja, memória e disco/storage do navegador podem estar
  /// temporariamente diferentes). Sempre `false` para
  /// [AllBoxBackendKind.memory], que não tem janela de debounce.
  final bool pendingFlush;

  /// A read-only copy of every key/value currently in memory for this
  /// container. Safe to hold onto — mutating the live container afterwards
  /// does not change this snapshot.
  ///
  /// **PT-BR:** Uma cópia somente-leitura de todas as chaves/valores
  /// atualmente em memória para este container. Seguro de guardar — mutar o
  /// container ao vivo depois não muda este retrato.
  final Map<String, dynamic> entries;

  /// Rough estimate, in bytes, of [entries] once JSON-encoded. Best-effort:
  /// falls back to a cheap non-JSON estimate if a value isn't
  /// JSON-encodable (same values [AllBox.write] would already have warned
  /// about via [allBoxDebugLog]).
  ///
  /// **PT-BR:** Estimativa aproximada, em bytes, de [entries] uma vez
  /// codificado em JSON. Best-effort: recorre a uma estimativa mais barata
  /// e não-JSON se algum valor não for JSON-encodável (os mesmos valores
  /// sobre os quais [AllBox.write] já teria avisado via [allBoxDebugLog]).
  final int approximateSizeBytes;

  /// All keys currently stored in this container. Shorthand for
  /// `entries.keys`.
  ///
  /// **PT-BR:** Todas as chaves atualmente armazenadas neste container.
  /// Atalho para `entries.keys`.
  Iterable<String> get keys => entries.keys;

  /// Number of keys currently stored in this container.
  ///
  /// **PT-BR:** Quantidade de chaves atualmente armazenadas neste
  /// container.
  int get length => entries.length;

  /// A JSON-safe representation of this snapshot, used by
  /// [AllBoxInspector.snapshotAsJson] to hand data across a VM Service
  /// `eval` boundary (e.g. to a DevTools extension) as a single `String`,
  /// without the caller needing `dart:convert` in scope at the eval
  /// call site.
  ///
  /// [entries] is encoded key-by-key: any value that isn't JSON-encodable
  /// (the same condition [AllBox.write] already warns about via
  /// [allBoxDebugLog]) is replaced with a
  /// `'<non-JSON-encodable: SomeType>'` placeholder string instead of
  /// making the whole snapshot fail to serialize.
  ///
  /// **PT-BR:** Uma representação JSON-safe deste retrato, usada por
  /// [AllBoxInspector.snapshotAsJson] para passar dados através de uma
  /// fronteira de `eval` da VM Service (ex.: para uma extensão do
  /// DevTools) como uma única `String`, sem que quem chama precise ter
  /// `dart:convert` no escopo no local do eval.
  ///
  /// [entries] é codificado chave a chave: qualquer valor que não seja
  /// JSON-encodável (a mesma condição sobre a qual [AllBox.write] já avisa
  /// via [allBoxDebugLog]) é substituído por uma string placeholder
  /// `'<non-JSON-encodable: AlgumTipo>'`, em vez de fazer o retrato inteiro
  /// falhar ao serializar.
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'container': container,
      'isInitialized': isInitialized,
      'backend': backend.name,
      'pendingFlush': pendingFlush,
      'entries': _jsonSafeEntries(entries),
      'approximateSizeBytes': approximateSizeBytes,
    };
  }

  static Map<String, dynamic> _jsonSafeEntries(Map<String, dynamic> entries) {
    final safe = <String, dynamic>{};
    for (final e in entries.entries) {
      try {
        jsonEncode(e.value);
        safe[e.key] = e.value;
      } on Object {
        safe[e.key] = '<non-JSON-encodable: ${e.value.runtimeType}>';
      }
    }
    return safe;
  }

  @override
  String toString() => 'AllBoxContainerSnapshot(container: $container, '
      'isInitialized: $isInitialized, backend: $backend, '
      'pendingFlush: $pendingFlush, ${entries.length} keys, '
      '~$approximateSizeBytes bytes)';
}
