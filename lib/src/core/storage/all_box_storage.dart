/// How strongly a [AllBoxStorage.save] call must guarantee durability.
///
/// Mirrors `AllBox`'s durability ladder: [save] is the cheap tier (survives
/// an app crash but not necessarily a power loss — no forced fsync on IO),
/// [flush] is the strong tier (forces an fsync on IO, so it survives a power
/// loss too). On platforms without a meaningful distinction (Web, in-memory),
/// both are treated identically.
///
/// **PT-BR:** O quão forte uma chamada de [AllBoxStorage.save] deve
/// garantir durabilidade.
///
/// Espelha a escada de durabilidade do `AllBox`: [save] é o nível barato
/// (sobrevive a um crash do app, mas não necessariamente a uma queda de
/// energia — sem fsync forçado no IO), [flush] é o nível forte (força um
/// fsync no IO, então sobrevive também a queda de energia). Em plataformas
/// sem uma distinção significativa (Web, em memória), ambos são tratados de
/// forma idêntica.
enum AllBoxPersistMode {
  /// Cheap durability tier: survives an app crash, not necessarily a power
  /// loss / OS crash.
  ///
  /// **PT-BR:** Nível barato de durabilidade: sobrevive a um crash do app,
  /// não necessariamente a uma queda de energia / crash do OS.
  save,

  /// Strong durability tier: forces the strongest guarantee the platform can
  /// offer (e.g. `fsync` on IO).
  ///
  /// **PT-BR:** Nível forte de durabilidade: força a garantia mais forte que
  /// a plataforma pode oferecer (ex.: `fsync` no IO).
  flush,
}

/// The storage seam behind [AllBox]: however a container's data is actually
/// persisted (disk file, browser storage, plain memory, or anything a
/// caller wants to plug in), it goes through this interface.
///
/// [AllBox] itself owns the in-memory map, the optimistic writes, the
/// listener notifications and the debounce/coalescing of flushes — none of
/// that is duplicated per implementation. An [AllBoxStorage] only needs to
/// know how to load a full snapshot, save a full snapshot, delete it, and
/// release any resources it holds.
///
/// This is public mainly so advanced callers/tests can implement their own
/// [AllBoxStorage] (e.g. to inject a fake in tests, or to back `AllBox` with
/// something this package doesn't ship a storage for) and pass it to
/// `AllBox.init(..., storage: myStorage)`. Everyday usage never needs to
/// touch this — see `AllBox.init` (disk), `AllBox.memory` (tests) instead.
///
/// **PT-BR:** A costura de storage por trás do [AllBox]: seja como for que
/// os dados de um container são de fato persistidos (arquivo em disco,
/// storage do navegador, memória pura, ou qualquer coisa que quem chama
/// queira conectar), isso passa por esta interface.
///
/// O próprio [AllBox] é dono do map em memória, das escritas otimistas, das
/// notificações de listeners e do debounce/coalescing de flushes — nada
/// disso é duplicado por implementação. Um [AllBoxStorage] só precisa saber
/// carregar um snapshot completo, salvar um snapshot completo, apagá-lo, e
/// liberar quaisquer recursos que segure.
///
/// Isso é público principalmente para que quem chama de forma avançada (ou
/// testes) possa implementar seu próprio [AllBoxStorage] (ex.: para injetar
/// um fake em testes, ou para usar o `AllBox` sobre algo que este pacote não
/// oferece um storage pronto) e passá-lo para
/// `AllBox.init(..., storage: meuStorage)`. O uso do dia a dia nunca precisa
/// tocar nisso — veja `AllBox.init` (disco) e `AllBox.memory` (testes).
abstract interface class AllBoxStorage {
  /// Whether this container has ever actually been persisted before, i.e.
  /// whether there is *some* previously-saved snapshot for it (even an
  /// intentionally empty one, e.g. left behind by a previous
  /// `AllBox.erase()`).
  ///
  /// Used by [AllBox.init] to decide whether an `initialData` seed should be
  /// applied: it is only ever applied on a genuine first run.
  ///
  /// **PT-BR:** Se este container já foi de fato persistido alguma vez, ou
  /// seja, se existe *algum* snapshot salvo anteriormente para ele (mesmo
  /// que intencionalmente vazio, ex.: deixado por um `AllBox.erase()`
  /// anterior).
  ///
  /// Usado pelo [AllBox.init] para decidir se um seed de `initialData` deve
  /// ser aplicado: ele só é aplicado em um first-run de verdade.
  Future<bool> hasPersistedData();

  /// Loads the last persisted snapshot for this container. Must never
  /// throw: any failure (missing data, corrupted data, unavailable storage)
  /// should result in an empty map instead of crashing the caller.
  ///
  /// **PT-BR:** Carrega o último snapshot persistido deste container. Nunca
  /// deve lançar exceção: qualquer falha (dado ausente, corrompido, storage
  /// indisponível) deve resultar em um map vazio, em vez de derrubar quem
  /// chamou.
  Future<Map<String, dynamic>> load();

  /// Persists [snapshot] as the entire, current state of this container,
  /// with the durability guarantee requested by [mode].
  ///
  /// **PT-BR:** Persiste [snapshot] como o estado atual e completo deste
  /// container, com a garantia de durabilidade pedida por [mode].
  Future<void> save(Map<String, dynamic> snapshot, {required AllBoxPersistMode mode});

  /// Permanently removes any persisted data for this container.
  ///
  /// **PT-BR:** Remove permanentemente qualquer dado persistido deste
  /// container.
  Future<void> delete();

  /// Releases any resources held by this storage (open handles, timers,
  /// etc). Safe to call even if nothing needs releasing.
  ///
  /// **PT-BR:** Libera quaisquer recursos mantidos por este storage (handles
  /// abertos, timers, etc). Seguro de chamar mesmo que não haja nada para
  /// liberar.
  Future<void> close();
}
