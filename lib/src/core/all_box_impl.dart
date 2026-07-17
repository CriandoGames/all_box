import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'storage/all_box_memory_storage.dart';
import 'storage/all_box_platform_storage.dart';
import 'storage/all_box_storage.dart';

export 'storage/all_box_storage.dart' show AllBoxStorage, AllBoxPersistMode;
export 'storage/all_box_storage_exception.dart' show AllBoxStorageException;

// Split out of this file via `part`/`part of` (not separate libraries) so
// that AllBoxInspector can read AllBox's private `_instances`/`_box`/`_flush`
// without a public listener/reactive API — see debug/all_box_inspector.dart.
part '../debug/all_box_container_snapshot.dart';
part '../debug/all_box_inspector.dart';

/// Describes a failed persistence operation after memory was already updated.
///
/// Reported through `AllBox.init(onPersistenceError: ...)`. The original
/// failure is available in [cause] and [stackTrace].
class AllBoxPersistenceError {
  /// Creates a persistence error report.
  AllBoxPersistenceError({
    required this.container,
    required this.operation,
    required this.cause,
    required this.stackTrace,
    required this.hasUnpersistedChanges,
  });

  /// The container whose persistence operation failed.
  final String container;

  /// The AllBox operation that attempted persistence.
  final String operation;

  /// The original error thrown by the storage backend.
  final Object cause;

  /// Stack trace captured with [cause].
  final StackTrace stackTrace;

  /// Whether memory may contain changes not yet persisted to storage.
  final bool hasUnpersistedChanges;

  @override
  String toString() {
    return 'AllBoxPersistenceError(container: $container, '
        'operation: $operation, hasUnpersistedChanges: '
        '$hasUnpersistedChanges, cause: $cause)';
  }
}

/// Whether the current build is a debug build.
///
/// Pure Dart equivalent of Flutter's `kDebugMode`, computed via [assert]
/// instead of depending on `package:flutter/foundation.dart`.
///
/// **PT-BR:** Se o build atual é um build de debug.
///
/// Equivalente em Dart puro do `kDebugMode` do Flutter, calculado via
/// [assert] em vez de depender de `package:flutter/foundation.dart`.
bool get allBoxDebugMode {
  var enabled = false;
  assert(() {
    enabled = true;
    return true;
  }());
  return enabled;
}

/// Prints [message] to the console, but only in debug builds (i.e. only
/// when asserts are enabled).
///
/// Pure Dart equivalent of Flutter's `debugPrint`.
///
/// **PT-BR:** Imprime [message] no console, mas somente em builds de debug
/// (ou seja, somente quando asserts estão habilitados).
///
/// Equivalente em Dart puro do `debugPrint` do Flutter.
void allBoxDebugLog(Object message) {
  assert(() {
    // ignore: avoid_print
    print(message);
    return true;
  }());
}

/// A synchronous, lightweight key-value storage container.
///
/// `AllBox` keeps all data in memory (in a `Map<String, dynamic>`), so every
/// read (`read`, `readOrDefault`, `hasData`, `getKeys`, `getValues`) is
/// synchronous and never touches the underlying storage. Writes are
/// optimistic: `write()` updates memory immediately; persisting happens
/// asynchronously afterwards, debounced so that bursts of writes generate a
/// single flush.
///
/// One physical unit of storage is used per *container* (a logical name),
/// not one per key. On IO platforms that's a `<container>.db` file (plus
/// `.tmp`/`.bak` companions); on Web it's a single `localStorage` key. Which
/// storage backend to use is resolved automatically from the compile
/// target — see [init].
///
/// **PT-BR:** Um storage key-value síncrono e leve.
///
/// O `AllBox` mantém todos os dados em memória (em um `Map<String,
/// dynamic>`), então toda leitura (`read`, `readOrDefault`, `hasData`,
/// `getKeys`, `getValues`) é síncrona e nunca toca o storage subjacente. As
/// escritas são otimistas: `write()` atualiza a memória imediatamente; a
/// persistência acontece depois, de forma assíncrona e com debounce, para
/// que várias escritas seguidas gerem um único flush.
///
/// Uma unidade física de storage é usada por *container* (um nome lógico),
/// não uma por chave. Em plataformas IO isso é um arquivo `<container>.db`
/// (mais os companheiros `.tmp`/`.bak`); na Web é uma única chave de
/// `localStorage`. Qual backend de storage usar é resolvido automaticamente
/// a partir do alvo de compilação — veja [init].
class AllBox {
  /// Returns the singleton [AllBox] instance for [container].
  ///
  /// Call [init] or [memory] before reading or writing unless the container
  /// has already been initialized elsewhere.
  factory AllBox([String container = defaultContainerName]) {
    return _instances.putIfAbsent(container, () => AllBox._internal(container));
  }

  AllBox._internal(this.container);

  /// The container name used when none is supplied.
  ///
  /// **PT-BR:** Nome do container usado quando nenhum é informado.
  static const String defaultContainerName = 'AllBox';

  /// Default debounce window used to coalesce successive [write] calls into
  /// a single flush. Configurable per container via [init].
  ///
  /// **PT-BR:** Janela de debounce padrão usada para agrupar chamadas
  /// sucessivas de [write] em um único flush. Configurável por container
  /// via [init].
  static const Duration defaultFlushDelay = Duration(milliseconds: 100);

  /// The logical name of this container. On IO, each container is
  /// persisted to its own file (`<container>.db`) inside the directory
  /// passed to [init]; on Web, to its own `localStorage` key.
  ///
  /// **PT-BR:** Nome lógico deste container. No IO, cada container é
  /// persistido em seu próprio arquivo (`<container>.db`) dentro do
  /// diretório passado para [init]; na Web, em sua própria chave de
  /// `localStorage`.
  final String container;

  static final Map<String, AllBox> _instances = <String, AllBox>{};
  static final Map<String, _PendingInitialization> _pendingInitializations =
      <String, _PendingInitialization>{};

  /// In-memory, synchronously-readable data for this container.
  ///
  /// **PT-BR:** Dados em memória deste container, lidos de forma síncrona.
  final Map<String, dynamic> _box = <String, dynamic>{};

  _FlushCoordinator? _flush;
  void Function(AllBoxPersistenceError error)? _onPersistenceError;
  bool _initialized = false;

  /// Whether [init] (or [memory]) has already completed for this container.
  ///
  /// **PT-BR:** Se [init] (ou [memory]) já foi concluído para este
  /// container.
  bool get isInitialized => _initialized;

  /// Initializes [container], loading its data into memory so that
  /// subsequent reads are synchronous, and returns the initialized [AllBox]
  /// instance (the same one returned by `AllBox(container)` afterwards).
  ///
  /// Which storage backend is used is resolved automatically from the
  /// compile target, unless [storage] is explicitly supplied:
  ///  * On **Web**, `window.localStorage` is used automatically; [path], if
  ///    supplied, is silently ignored (harmless for code shared across IO
  ///    and Web).
  ///  * On **IO** platforms (native VM/AOT — including Flutter mobile,
  ///    desktop), [path] is required: the directory where `<container>.db`
  ///    (and its `.tmp`/`.bak` companions) live. Resolving this path (e.g.
  ///    via `path_provider`, `getApplicationDocumentsDirectory`, or any
  ///    other means) is entirely the caller's responsibility — `AllBox`
  ///    deliberately never does this itself. Omitting it throws an
  ///    `AllBoxStorageException` with a clear message.
  ///  * [storage] is an advanced escape hatch: pass your own `AllBoxStorage`
  ///    implementation to bypass automatic platform resolution entirely
  ///    (e.g. to inject a fake in a test, or to back `AllBox` with
  ///    something this package doesn't ship a storage for). It always takes
  ///    priority over the automatic resolution above.
  ///
  /// [initialData], if non-empty, is only ever applied on a genuine first
  /// run — i.e. when this container has never been persisted before. It
  /// seeds the container with default values (e.g. onboarding flags,
  /// default settings) so callers don't need a separate `write()` right
  /// after `init()`. It is persisted immediately (bypassing the debounce
  /// window), so the seed survives a crash right after first launch. If the
  /// container was already persisted before — even as an intentionally
  /// empty `{}` written by a previous [erase] — [initialData] is ignored and
  /// whatever was already persisted wins, exactly like a normal [init] call.
  ///
  /// Calling [init] again for a container that is already initialized is a
  /// no-op; the container keeps whatever data it currently holds in memory.
  ///
  /// [validateContainerName] is opt-in for compatibility. When true on IO,
  /// the built-in storage rejects names that can behave differently across
  /// operating systems or be interpreted as paths (for example `../data`,
  /// `a/b`, `cache:name`, `CON`, `NUL`). Existing applications that already
  /// use such names can keep the default false and migrate deliberately.
  ///
  /// [experimentalIndexedDbBackend] is an explicit Web-only opt-in for the
  /// IndexedDB migration backend while it is being validated. The default
  /// remains `window.localStorage`. It is ignored when [storage] is supplied.
  ///
  /// **PT-BR:** Inicializa [container], carregando seus dados para a
  /// memória, para que as leituras seguintes sejam síncronas, e retorna a
  /// instância inicializada de [AllBox] (a mesma que `AllBox(container)`
  /// retorna depois).
  ///
  /// Qual backend de storage é usado é resolvido automaticamente a partir
  /// do alvo de compilação, a menos que [storage] seja explicitamente
  /// informado:
  ///  * Na **Web**, o `window.localStorage` é usado automaticamente; [path],
  ///    se informado, é silenciosamente ignorado (inofensivo para código
  ///    compartilhado entre IO e Web).
  ///  * Em plataformas **IO** (VM/AOT nativa — incluindo Flutter
  ///    mobile/desktop), [path] é obrigatório: o diretório onde
  ///    `<container>.db` (e seus companheiros `.tmp`/`.bak`) ficam. Resolver
  ///    esse path (via `path_provider`, `getApplicationDocumentsDirectory`,
  ///    ou qualquer outro meio) é responsabilidade inteiramente de quem
  ///    chama — o `AllBox` deliberadamente nunca faz isso sozinho. Omiti-lo
  ///    lança uma `AllBoxStorageException` com mensagem clara.
  ///  * [storage] é uma via de escape avançada: passe sua própria
  ///    implementação de `AllBoxStorage` para pular a resolução automática
  ///    de plataforma por completo (ex.: para injetar um fake em teste, ou
  ///    para usar o `AllBox` sobre algo que este pacote não oferece um
  ///    storage pronto). Sempre tem prioridade sobre a resolução automática
  ///    acima.
  ///
  /// [initialData], se não vazio, só é aplicado em um first-run de
  /// verdade — ou seja, quando este container nunca foi persistido antes.
  /// Ele popula o container com valores default (ex.: flags de onboarding,
  /// configurações padrão), evitando um `write()` separado logo após o
  /// `init()`. É persistido imediatamente (ignorando a janela de debounce),
  /// então o seed sobrevive a um crash logo após o primeiro lançamento do
  /// app. Se o container já tinha sido persistido antes — mesmo que como um
  /// `{}` intencionalmente vazio escrito por um [erase] anterior —
  /// [initialData] é ignorado e o que já estava persistido prevalece,
  /// exatamente como em uma chamada normal de [init].
  ///
  /// Chamar [init] novamente para um container já inicializado é um no-op;
  /// o container mantém os dados que já tinha em memória.
  ///
  /// [experimentalIndexedDbBackend] é um opt-in explícito, somente Web, para
  /// o backend IndexedDB com migração enquanto ele é validado. O padrão
  /// continua sendo `window.localStorage`. É ignorado quando [storage] é
  /// informado.
  static Future<AllBox> init(
    String container, {
    String? path,
    Duration flushDelay = defaultFlushDelay,
    Map<String, dynamic> initialData = const <String, dynamic>{},
    AllBoxStorage? storage,
    void Function(AllBoxPersistenceError error)? onPersistenceError,
    bool validateContainerName = false,
    bool experimentalIndexedDbBackend = false,
  }) async {
    final box = AllBox(container);
    if (box._initialized) return box;

    final config = _InitializationConfig(
      path: path,
      flushDelay: flushDelay,
      initialData: initialData,
      storage: storage,
      onPersistenceError: onPersistenceError,
      validateContainerName: validateContainerName,
      experimentalIndexedDbBackend: experimentalIndexedDbBackend,
    );
    final pending = _pendingInitializations[container];
    if (pending != null) {
      if (pending.config == config) return pending.future;
      throw StateError(
        'AllBox("$container") is already being initialized with different '
        'options. Concurrent init() calls for the same container must use '
        'equivalent path, storage, initialData, flushDelay, '
        'onPersistenceError, validateContainerName and '
        'experimentalIndexedDbBackend values.',
      );
    }

    late final Future<AllBox> future;
    future = box
        ._initialize(
      path: path,
      flushDelay: flushDelay,
      initialData: initialData,
      storage: storage,
      onPersistenceError: onPersistenceError,
      validateContainerName: validateContainerName,
      experimentalIndexedDbBackend: experimentalIndexedDbBackend,
    )
        .whenComplete(() {
      if (identical(_pendingInitializations[container]?.future, future)) {
        _pendingInitializations.remove(container);
      }
    });
    _pendingInitializations[container] = _PendingInitialization(config, future);
    return future;
  }

  Future<AllBox> _initialize({
    required String? path,
    required Duration flushDelay,
    required Map<String, dynamic> initialData,
    required AllBoxStorage? storage,
    required void Function(AllBoxPersistenceError error)? onPersistenceError,
    required bool validateContainerName,
    required bool experimentalIndexedDbBackend,
  }) async {
    final resolvedStorage = storage ??
        AllBoxPlatformStorage.resolve(
          container: container,
          path: path,
          validateContainerName: validateContainerName,
          experimentalIndexedDbBackend: experimentalIndexedDbBackend,
        );
    _onPersistenceError = onPersistenceError;
    final coordinator = _DebouncedFlushCoordinator(
      resolvedStorage,
      flushDelay,
      onPersistenceError: _reportPersistenceError,
    );

    try {
      final isFirstRun = !(await resolvedStorage.hasPersistedData());
      final data = await resolvedStorage.load();

      _flush = coordinator;
      if (isFirstRun && initialData.isNotEmpty) {
        _box
          ..clear()
          ..addAll(initialData);
        // Persist the seed right away so it isn't lost if the process dies
        // before the first real write() would have flushed it.
        await coordinator.flushNow(_box, operation: 'init');
      } else {
        _box
          ..clear()
          ..addAll(data);
      }
      _initialized = true;
      return this;
    } on Object {
      coordinator.disposeForTesting();
      if (identical(_flush, coordinator)) {
        _flush = null;
      }
      _box.clear();
      _initialized = false;
      rethrow;
    }
  }

  /// Initializes [container] with a pure in-memory storage: no real disk
  /// I/O, no browser storage, no real [Timer]. Every [write] is "flushed"
  /// synchronously into an in-memory snapshot instead of a debounce window.
  ///
  /// [initialData] always seeds the container, unconditionally (there is no
  /// "first run" concept here — every call to [memory] starts from a brand
  /// new, empty in-memory storage).
  ///
  /// Intended for apps/packages that *consume* `all_box` and want to
  /// unit/widget-test their own code against a real [AllBox] instance,
  /// without the flakiness or setup cost of real filesystem/browser access.
  /// It is also what removes the only source of a real, pending [Timer]
  /// that [init] would otherwise schedule on the first [write] — which
  /// matters specifically inside `testWidgets`, since its `FakeAsync` zone
  /// expects every [Timer] to resolve before the test ends; a real one left
  /// pending there can hang the test runner instead of failing it.
  ///
  /// This is the recommended replacement for the older
  /// `initWithMemoryBackendForTesting`.
  ///
  /// **PT-BR:** Inicializa [container] com um storage puramente em memória:
  /// sem I/O real em disco, sem storage de navegador, sem [Timer] real. Todo
  /// [write] é "flushado" de forma síncrona em um snapshot em memória, em
  /// vez de uma janela de debounce.
  ///
  /// [initialData] sempre semeia o container, incondicionalmente (não há
  /// conceito de "first run" aqui — cada chamada a [memory] começa de um
  /// storage em memória novo e vazio).
  ///
  /// Feito para apps/pacotes que *consomem* o `all_box` e querem testar
  /// (unit/widget) o próprio código contra uma instância real de [AllBox],
  /// sem o custo/flakiness de acesso real a sistema de arquivos/navegador.
  /// É também o que elimina a única fonte de um [Timer] real pendente que
  /// um [init] normal agendaria no primeiro [write] — o que importa
  /// especificamente dentro de `testWidgets`, já que sua zona `FakeAsync`
  /// espera que todo [Timer] seja resolvido antes do teste terminar; um
  /// real deixado pendente ali pode travar o test runner em vez de falhar
  /// o teste.
  ///
  /// É a substituta recomendada do antigo
  /// `initWithMemoryBackendForTesting`.
  static Future<AllBox> memory(
    String container, {
    Map<String, dynamic> initialData = const <String, dynamic>{},
  }) async {
    final box = AllBox(container);
    if (box._initialized) return box;

    box._flush = _ImmediateFlushCoordinator(AllBoxMemoryStorage());
    box._box
      ..clear()
      ..addAll(initialData);
    box._initialized = true;
    return box;
  }

  /// Reads [key] synchronously, returning `null` if it is absent or stored
  /// under a different type than [T].
  ///
  /// **PT-BR:** Lê [key] de forma síncrona, retornando `null` se ela não
  /// existir ou estiver armazenada sob um tipo diferente de [T].
  T? read<T>(String key) {
    final dynamic value = _box[key];
    if (value is T) return value;
    return null;
  }

  /// Reads [key] synchronously, returning [fallback] if it is absent or
  /// stored under a different type than [T].
  ///
  /// **PT-BR:** Lê [key] de forma síncrona, retornando [fallback] se ela
  /// não existir ou estiver armazenada sob um tipo diferente de [T].
  T readOrDefault<T>(String key, T fallback) {
    return read<T>(key) ?? fallback;
  }

  /// Whether [key] currently exists in this container.
  ///
  /// **PT-BR:** Se [key] existe atualmente neste container.
  bool hasData(String key) => _box.containsKey(key);

  /// All keys currently stored in this container.
  ///
  /// **PT-BR:** Todas as chaves atualmente armazenadas neste container.
  Iterable<String> getKeys() => _box.keys;

  /// All values currently stored in this container.
  ///
  /// **PT-BR:** Todos os valores atualmente armazenados neste container.
  Iterable<dynamic> getValues() => _box.values;

  /// Writes [value] under [key].
  ///
  /// This is optimistic: the in-memory map is updated synchronously, before
  /// this method returns. The underlying persistence is scheduled
  /// asynchronously and debounced — several `write()` calls in quick
  /// succession result in a single flush.
  ///
  /// **PT-BR:** Escreve [value] em [key].
  ///
  /// Isso é otimista: o mapa em memória é atualizado de forma síncrona,
  /// antes deste método retornar. A persistência subjacente é agendada de
  /// forma assíncrona e com debounce — várias chamadas de `write()` em
  /// sequência rápida resultam em um único flush.
  void write(String key, dynamic value) {
    _assertInitialized('write');
    _warnIfNotSerializable('write', key, value);
    _box[key] = value;
    _flush!.scheduleFlush(_box);
    _debugPostMutationEvent('write', key: key);
  }

  /// Like [write], but returns a [Future] that only completes once the new
  /// value has actually been persisted (bypassing the debounce window).
  ///
  /// **PT-BR:** Igual a [write], mas retorna um [Future] que só completa
  /// quando o novo valor tiver sido de fato persistido (ignorando a janela
  /// de debounce).
  Future<void> writeAndFlush(String key, dynamic value) async {
    _assertInitialized('writeAndFlush');
    _warnIfNotSerializable('writeAndFlush', key, value);
    _box[key] = value;
    _debugPostMutationEvent('write', key: key);
    await _flush!.flushNow(_box, operation: 'writeAndFlush');
  }

  /// Like [write], but returns a [Future] that completes once the new value
  /// has been handed off for persistence (bypassing the debounce window) —
  /// **without** forcing the strongest durability guarantee the storage can
  /// offer (e.g. no forced `fsync` on IO).
  ///
  /// This is the intermediate durability tier, equivalent to what
  /// `Hive.put`-style APIs offer: when the [Future] completes, the data
  /// survives an app crash, but not necessarily a power loss / OS crash on
  /// IO platforms (the OS may still be holding it in its page cache). It
  /// keeps the full write-ahead + atomic-rename pipeline on IO, so the
  /// container file can never be left half-written. It is orders of
  /// magnitude cheaper than [writeAndFlush], whose `fsync` is the only
  /// guarantee that survives power loss.
  ///
  /// Durability ladder: [write] (optimistic, debounced) → [writeAndSave]
  /// (waits for the OS write) → [writeAndFlush] (waits for `fsync`). On Web,
  /// [writeAndSave] and [writeAndFlush] behave identically — there's no
  /// meaningful distinction to make on top of a synchronous
  /// `localStorage.setItem`.
  ///
  /// **PT-BR:** Igual a [write], mas retorna um [Future] que completa
  /// quando o novo valor foi entregue para persistência (ignorando a janela
  /// de debounce) — **sem** forçar a garantia de durabilidade mais forte
  /// que o storage pode oferecer (ex.: sem `fsync` forçado no IO).
  ///
  /// É o nível intermediário de durabilidade, equivalente ao que APIs
  /// estilo `Hive.put` oferecem: quando o [Future] completa, o dado
  /// sobrevive a um crash do app, mas não necessariamente a uma queda de
  /// energia / crash do OS em plataformas IO (o OS ainda pode estar
  /// segurando o dado no page cache). Mantém o pipeline completo de
  /// write-ahead + rename atômico no IO, então o arquivo do container nunca
  /// fica meio-escrito. É ordens de magnitude mais barato que
  /// [writeAndFlush], cujo `fsync` é a única garantia que sobrevive a queda
  /// de energia.
  ///
  /// Escada de durabilidade: [write] (otimista, debounced) →
  /// [writeAndSave] (espera o write do OS) → [writeAndFlush] (espera o
  /// `fsync`). Na Web, [writeAndSave] e [writeAndFlush] se comportam de
  /// forma idêntica — não há distinção significativa a fazer sobre um
  /// `localStorage.setItem` síncrono.
  Future<void> writeAndSave(String key, dynamic value) async {
    _assertInitialized('writeAndSave');
    _warnIfNotSerializable('writeAndSave', key, value);
    _box[key] = value;
    _debugPostMutationEvent('write', key: key);
    await _flush!.flushNow(_box, fsync: false, operation: 'writeAndSave');
  }

  /// Removes [key], if it was present.
  ///
  /// **PT-BR:** Remove [key], se ela existia.
  void remove(String key) {
    _assertInitialized('remove');
    if (!_box.containsKey(key)) return;
    _box.remove(key);
    _flush!.scheduleFlush(_box);
    _debugPostMutationEvent('remove', key: key);
  }

  /// Clears every key in this container.
  ///
  /// **PT-BR:** Limpa todas as chaves deste container.
  void erase() {
    _assertInitialized('erase');
    _box.clear();
    _flush!.scheduleFlush(_box);
    _debugPostMutationEvent('erase');
  }

  /// Forces an immediate flush, ignoring the debounce window.
  ///
  /// Intended to be called e.g. from `AppLifecycleState.paused`, to make
  /// sure nothing pending is lost if the process is about to be killed.
  ///
  /// **PT-BR:** Força um flush imediato, ignorando a janela de debounce.
  ///
  /// Feito para ser chamado, por exemplo, a partir de
  /// `AppLifecycleState.paused`, para garantir que nada pendente se perca
  /// caso o processo seja finalizado.
  Future<void> flushNow() async {
    _assertInitialized('flushNow');
    await _flush!.flushNow(_box, operation: 'flushNow');
  }

  void _reportPersistenceError(
    String operation,
    Object cause,
    StackTrace stackTrace,
    bool hasUnpersistedChanges,
  ) {
    final error = AllBoxPersistenceError(
      container: container,
      operation: operation,
      cause: cause,
      stackTrace: stackTrace,
      hasUnpersistedChanges: hasUnpersistedChanges,
    );
    _onPersistenceError?.call(error);
  }

  /// Releases this container and removes it from the internal registry.
  ///
  /// When [flushPending] is true, any pending in-memory changes are flushed
  /// before the underlying storage is closed. When false, pending debounced
  /// writes are discarded.
  Future<void> close({bool flushPending = true}) async {
    final coordinator = _flush;
    if (coordinator == null) {
      _initialized = false;
      if (identical(_instances[container], this)) {
        _instances.remove(container);
      }
      return;
    }

    try {
      await coordinator.close(_box, flushPending: flushPending);
    } finally {
      if (identical(_flush, coordinator)) {
        _flush = null;
      }
      _box.clear();
      _initialized = false;
      if (identical(_instances[container], this)) {
        _instances.remove(container);
      }
    }
  }

  /// Destroys this container's persisted data and releases its storage.
  ///
  /// This is a logical deletion API, not a secure wipe: storage media may
  /// retain old bytes outside this package's control.
  Future<void> destroy() async {
    final coordinator = _flush;
    if (coordinator == null) {
      _box.clear();
      _initialized = false;
      if (identical(_instances[container], this)) {
        _instances.remove(container);
      }
      return;
    }

    try {
      await coordinator.destroy(_box);
    } finally {
      if (identical(_flush, coordinator)) {
        _flush = null;
      }
      _box.clear();
      _initialized = false;
      if (identical(_instances[container], this)) {
        _instances.remove(container);
      }
    }
  }

  void _assertInitialized(String method) {
    if (!_initialized || _flush == null) {
      throw StateError(
        'AllBox("$container").$method() called before initialization. '
        "Call `await AllBox.init('$container', path: yourDirectoryPath)` "
        '(or `await AllBox.memory(\'$container\')` in tests) first (for '
        'example in `main()`, after '
        '`WidgetsFlutterBinding.ensureInitialized()`).',
      );
    }
  }

  /// In debug builds only, warns loudly (via [debugPrint], wrapped in ANSI
  /// red) if [value] is not JSON-encodable. Never throws and never blocks
  /// [write]/[writeAndFlush] — the value is still written to memory and
  /// still handed off to the flush pipeline exactly as-is, same as
  /// `GetStorage`. If it truly can't be encoded, it will simply fail again,
  /// silently, inside the flush (already handled there via `debugPrint` for
  /// the debounced path, or via a rejected `Future` for
  /// `writeAndFlush`/`flushNow`).
  ///
  /// This is intentionally a warning, not a fail-fast `ArgumentError`: a
  /// production app should never crash because a caller stored a
  /// `DateTime`, an `enum` without `toJson()`, or some other non-encodable
  /// value — it should just be told about it, loudly, while developing.
  ///
  /// **PT-BR:** Somente em builds de debug, avisa de forma bem visível (via
  /// [debugPrint], com ANSI vermelho) se [value] não for JSON-encodável.
  /// Nunca lança exceção e nunca bloqueia [write]/[writeAndFlush] — o valor
  /// continua sendo escrito em memória e repassado ao pipeline de flush do
  /// jeito que está, igual ao `GetStorage`. Se de fato não puder ser
  /// codificado, ele vai falhar de novo, silenciosamente, lá dentro do
  /// flush (já tratado ali via `debugPrint` no caminho debounced, ou via
  /// `Future` rejeitada em `writeAndFlush`/`flushNow`).
  ///
  /// Isso é intencionalmente um aviso, não um `ArgumentError` fail-fast: um
  /// app em produção não deveria nunca quebrar porque alguém gravou um
  /// `DateTime`, um `enum` sem `toJson()`, ou outro valor não codificável —
  /// deveria só ser avisado disso, bem alto, durante o desenvolvimento.
  void _warnIfNotSerializable(String method, String key, dynamic value) {
    if (!allBoxDebugMode) return;
    try {
      jsonEncode(value);
    } on Object catch (error) {
      allBoxDebugLog(
        '\x1B[31mAllBox("$container").$method(\'$key\', ...): value is not '
        'JSON-encodable ($error). It was written to memory anyway, but it '
        'will silently fail to reach disk. All values must be '
        'JSON-encodable (String, num, bool, null, List, Map, or an object '
        'with a toJson() that returns one of those).\x1B[0m',
      );
    }
  }

  /// Posts a debug-only VM Service extension event so external tooling
  /// (e.g. a DevTools extension) can react to a mutation without polling
  /// [AllBoxInspector.snapshot]/[AllBoxInspector.snapshotAsJson].
  ///
  /// This is **not** a Dart-level listener/reactive API: there is no
  /// callback list, no `Stream`, nothing any Dart code — including this
  /// package's own — can subscribe to. `developer.postEvent` only ever
  /// reaches tooling attached over the VM Service protocol (e.g. DevTools
  /// or a debugger), and only does anything when something is actually
  /// listening on the `Extension` stream; from `write()`/`remove()`/
  /// `erase()`'s point of view it's exactly as inert as a `print()`
  /// nobody reads. `all_box`'s public promise from `0.4.0` — "write(),
  /// remove() and erase() only update memory and schedule persistence;
  /// they never notify anything" — is about *Dart-visible* notification,
  /// which this does not add.
  ///
  /// Guarded by [allBoxDebugMode], same as [allBoxDebugLog] and
  /// [_warnIfNotSerializable]: a no-op in release builds.
  ///
  /// **PT-BR:** Posta um evento de extensão da VM Service, somente em
  /// debug, para que ferramentas externas (ex.: uma extensão do DevTools)
  /// possam reagir a uma mutação sem fazer polling de
  /// [AllBoxInspector.snapshot]/[AllBoxInspector.snapshotAsJson].
  ///
  /// Isto **não** é uma API de listener/reatividade em nível Dart: não há
  /// lista de callbacks, nem `Stream`, nada que código Dart — nem deste
  /// próprio pacote — possa assinar. `developer.postEvent` só chega a
  /// ferramentas conectadas via protocolo da VM Service (ex.: DevTools ou
  /// um debugger), e só faz algo quando alguém de fato está ouvindo o
  /// stream `Extension`; do ponto de vista de `write()`/`remove()`/
  /// `erase()`, é tão inerte quanto um `print()` que ninguém lê. A
  /// promessa pública do `all_box` desde a `0.4.0` — "write(), remove() e
  /// erase() só atualizam a memória e agendam persistência; nunca
  /// notificam nada" — é sobre notificação *visível para código Dart*,
  /// que isto não adiciona.
  ///
  /// Guardado por [allBoxDebugMode], igual a [allBoxDebugLog] e
  /// [_warnIfNotSerializable]: um no-op em builds de release.
  void _debugPostMutationEvent(String op, {String? key}) {
    if (!allBoxDebugMode) return;
    developer.postEvent(AllBoxInspector.mutationEventKind, <String, dynamic>{
      'container': container,
      'op': op,
      if (key != null) 'key': key,
    });
  }

  /// Removes this container's cached singleton instance and cancels any
  /// pending debounce timer, without touching whatever was already
  /// persisted. Intended for tests; not part of the stable public API.
  ///
  /// **PT-BR:** Remove a instância singleton em cache deste container e
  /// cancela qualquer timer de debounce pendente, sem tocar no que já foi
  /// persistido. Feito para testes; não faz parte da API pública estável.
  static void resetInstanceForTesting(String container) {
    final box = _instances.remove(container);
    box?._flush?.disposeForTesting();
  }

  /// Number of times this container has actually flushed since [init] (or
  /// [memory]). Intended for tests that need a deterministic way to assert
  /// on debounce behavior, instead of watching the filesystem for
  /// notifications (unreliable on Windows). Not part of the stable public
  /// API.
  ///
  /// **PT-BR:** Quantidade de vezes que este container de fato fez flush
  /// desde o [init] (ou [memory]). Feito para testes que precisam de uma
  /// forma determinística de verificar o comportamento de debounce, em vez
  /// de observar o sistema de arquivos por notificações (instável no
  /// Windows). Não faz parte da API pública estável.
  int get flushCountForTesting => _flush?.flushCallCountForTesting ?? 0;

  /// Initializes [container] with a pure in-memory backend: no real disk
  /// I/O, no real [Timer], no temp directory required.
  ///
  /// Deprecated in favor of [memory], which is the same thing under a
  /// shorter, non-testing-flavored name, promoted to stable public API.
  ///
  /// **PT-BR:** Inicializa [container] com um backend puramente em memória:
  /// sem I/O real em disco, sem [Timer] real, sem precisar de diretório
  /// temporário.
  ///
  /// Descontinuado em favor de [memory], que é a mesma coisa com um nome
  /// mais curto e não voltado para testes, promovido a API pública
  /// estável.
  @Deprecated('Use AllBox.memory() instead.')
  static Future<void> initWithMemoryBackendForTesting(
    String container, {
    Map<String, dynamic> initialValues = const <String, dynamic>{},
  }) async {
    await memory(container, initialData: initialValues);
  }
}

class _PendingInitialization {
  _PendingInitialization(this.config, this.future);

  final _InitializationConfig config;
  final Future<AllBox> future;
}

class _InitializationConfig {
  _InitializationConfig({
    required this.path,
    required this.flushDelay,
    required Map<String, dynamic> initialData,
    required this.storage,
    required this.onPersistenceError,
    required this.validateContainerName,
    required this.experimentalIndexedDbBackend,
  }) : initialData = Map<String, dynamic>.of(initialData);

  final String? path;
  final Duration flushDelay;
  final Map<String, dynamic> initialData;
  final AllBoxStorage? storage;
  final void Function(AllBoxPersistenceError error)? onPersistenceError;
  final bool validateContainerName;
  final bool experimentalIndexedDbBackend;

  @override
  bool operator ==(Object other) {
    return other is _InitializationConfig &&
        path == other.path &&
        flushDelay == other.flushDelay &&
        identical(storage, other.storage) &&
        identical(onPersistenceError, other.onPersistenceError) &&
        validateContainerName == other.validateContainerName &&
        experimentalIndexedDbBackend == other.experimentalIndexedDbBackend &&
        _deepEquals(initialData, other.initialData);
  }

  @override
  int get hashCode => Object.hash(
        path,
        flushDelay,
        identityHashCode(storage),
        identityHashCode(onPersistenceError),
        validateContainerName,
        experimentalIndexedDbBackend,
        _deepHash(initialData),
      );
}

bool _deepEquals(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

int _deepHash(Object? value) {
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries
          .map((entry) => Object.hash(entry.key, _deepHash(entry.value))),
    );
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}

/// Internal seam between [AllBox] and the debounce/coalescing strategy used
/// to turn optimistic [AllBox.write] calls into calls against an
/// [AllBoxStorage]. Not exported.
///
/// [_DebouncedFlushCoordinator] is the strategy used by [AllBox.init] for
/// every real [AllBoxStorage] (IO, Web, or a caller-supplied one):
/// it debounces/coalesces bursts of writes into a single, serialized flush,
/// exactly like `all_box`'s original disk-only implementation did.
/// [_ImmediateFlushCoordinator] is the strategy used by [AllBox.memory]: no
/// [Timer], every write persists synchronously.
///
/// **PT-BR:** Costura interna entre [AllBox] e a estratégia de
/// debounce/coalescing usada para transformar chamadas otimistas de
/// [AllBox.write] em chamadas contra um [AllBoxStorage]. Não é exportada.
///
/// [_DebouncedFlushCoordinator] é a estratégia usada pelo [AllBox.init] para
/// todo [AllBoxStorage] real (IO, Web, ou um informado por quem chama): ela
/// debounça/coalesce bursts de escritas em um único flush serializado,
/// exatamente como a implementação original do `all_box`, só em disco,
/// fazia. [_ImmediateFlushCoordinator] é a estratégia usada pelo
/// [AllBox.memory]: sem [Timer], toda escrita persiste de forma síncrona.
abstract class _FlushCoordinator {
  void scheduleFlush(Map<String, dynamic> snapshot);
  Future<void> flushNow(
    Map<String, dynamic> snapshot, {
    bool fsync,
    String operation,
  });
  Future<void> close(
    Map<String, dynamic> snapshot, {
    required bool flushPending,
  });
  Future<void> destroy(Map<String, dynamic> snapshot);
  void disposeForTesting();
  int get flushCallCountForTesting;
}

/// Debounces and coalesces flushes against a single [AllBoxStorage],
/// regardless of what that storage actually is (disk file, `localStorage`,
/// or anything a caller plugs in). This is what removes the need to
/// duplicate the debounce/coalescing/serialized-queue logic in every
/// [AllBoxStorage] implementation.
///
/// **PT-BR:** Debounça e faz coalescing de flushes contra um único
/// [AllBoxStorage], independente do que esse storage realmente seja
/// (arquivo em disco, `localStorage`, ou qualquer coisa que quem chama
/// conecte). É isso que remove a necessidade de duplicar a lógica de
/// debounce/coalescing/fila serializada em cada implementação de
/// [AllBoxStorage].
class _DebouncedFlushCoordinator implements _FlushCoordinator {
  _DebouncedFlushCoordinator(
    this._storage,
    this.flushDelay, {
    required this.onPersistenceError,
  });

  final AllBoxStorage _storage;
  final Duration flushDelay;
  final void Function(
    String operation,
    Object cause,
    StackTrace stackTrace,
    bool hasUnpersistedChanges,
  ) onPersistenceError;

  Timer? _debounceTimer;
  bool _dirty = false;
  bool _closed = false;

  /// Number of times a flush actually ran against [_storage]. Only
  /// incremented for tests — counting real flushes this way is
  /// deterministic across platforms, unlike watching the filesystem for
  /// notifications (which is notoriously unreliable on Windows: events can
  /// be dropped, coalesced or delayed — see dart-lang/sdk#37233).
  ///
  /// **PT-BR:** Quantidade de vezes que um flush de fato rodou contra o
  /// [_storage]. Só é incrementado para testes — contar flushes reais dessa
  /// forma é determinístico em qualquer plataforma, ao contrário de
  /// observar o sistema de arquivos por notificações (notoriamente
  /// instável no Windows: eventos podem ser perdidos, agrupados ou
  /// atrasados — veja dart-lang/sdk#37233).
  @override
  int flushCallCountForTesting = 0;

  /// Chain used to serialize flushes: a new flush is only started after the
  /// previous one (successful or not) has finished, so two `save` calls
  /// never race against the same storage.
  ///
  /// **PT-BR:** Cadeia usada para serializar os flushes: um novo flush só
  /// começa depois que o anterior (com sucesso ou não) tiver terminado, de
  /// forma que duas chamadas de `save` nunca concorram no mesmo storage.
  Future<void> _flushChain = Future<void>.value();

  /// Snapshot waiting to be written by the next queued flush. While a flush
  /// is queued (but not yet running), every new flush request simply
  /// replaces this snapshot instead of enqueuing another full write — each
  /// snapshot is a copy of the *entire* box taken after the caller's write,
  /// so the newest one always contains every previous caller's data.
  ///
  /// **PT-BR:** Snapshot aguardando o próximo flush enfileirado. Enquanto um
  /// flush está na fila (mas ainda não rodando), cada novo pedido de flush
  /// apenas substitui este snapshot em vez de enfileirar outra gravação
  /// completa — cada snapshot é uma cópia do box *inteiro* tirada depois do
  /// write do caller, então o mais novo sempre contém os dados de todos os
  /// callers anteriores.
  Map<String, dynamic>? _pendingSnapshot;

  /// The [Future] shared by every caller coalesced into the next queued
  /// flush.
  ///
  /// **PT-BR:** O [Future] compartilhado por todos os callers coalescidos no
  /// próximo flush enfileirado.
  Future<void>? _pendingFlush;

  /// The durability mode the queued flush must honor. When callers with
  /// different durability levels coalesce into the same flush, the
  /// strongest requirement wins: one `writeAndFlush` among ten
  /// `writeAndSave`s makes the shared flush use [AllBoxPersistMode.flush].
  ///
  /// **PT-BR:** O modo de durabilidade que o flush enfileirado deve
  /// respeitar. Quando callers com níveis diferentes de durabilidade
  /// coalescem no mesmo flush, o requisito mais forte vence: um
  /// `writeAndFlush` entre dez `writeAndSave` faz o flush compartilhado
  /// usar [AllBoxPersistMode.flush].
  AllBoxPersistMode _pendingMode = AllBoxPersistMode.save;
  String _pendingOperation = 'flushNow';

  /// Schedules a coalesced flush: the first write of a burst arms a single
  /// [Timer]; every subsequent write within [flushDelay] just marks the
  /// container dirty and rides on the already-armed timer, so a burst still
  /// produces exactly one flush.
  ///
  /// **PT-BR:** Agenda um flush coalescido: a primeira escrita de um burst
  /// arma um único [Timer]; cada escrita seguinte dentro de [flushDelay] só
  /// marca o container como sujo e pega carona no timer já armado — um
  /// burst continua produzindo exatamente um flush.
  @override
  void scheduleFlush(Map<String, dynamic> snapshot) {
    if (_closed) return;
    _dirty = true;
    if (_debounceTimer?.isActive ?? false) {
      // A timer armed by an earlier write in this burst already covers this
      // write: the flush copies the live map when it fires.
      return;
    }
    _debounceTimer = Timer(flushDelay, () {
      if (!_dirty) return;
      _dirty = false;
      // This flush is fire-and-forget (nobody awaits it), so a failure here
      // must not become an unhandled Future error. Callers using
      // writeAndFlush()/flushNow() still see failures normally, since they
      // await _enqueueFlush's result directly.
      unawaited(
        _enqueueFlush(
          Map<String, dynamic>.of(snapshot),
          mode: AllBoxPersistMode.flush,
          operation: 'write',
        ).catchError((Object error, StackTrace stackTrace) {
          allBoxDebugLog(
            'AllBox: debounced flush failed and was dropped: $error',
          );
        }),
      );
    });
  }

  /// Cancels any pending debounced flush and flushes [snapshot] right away,
  /// still going through the serialized flush queue.
  ///
  /// **PT-BR:** Cancela qualquer flush com debounce pendente e grava
  /// [snapshot] imediatamente, ainda passando pela fila de flush
  /// serializada.
  @override
  Future<void> flushNow(
    Map<String, dynamic> snapshot, {
    bool fsync = true,
    String operation = 'flushNow',
  }) {
    if (_closed) {
      throw StateError('AllBox storage coordinator is closed.');
    }
    _debounceTimer?.cancel();
    _dirty = false;
    return _enqueueFlush(
      Map<String, dynamic>.of(snapshot),
      mode: fsync ? AllBoxPersistMode.flush : AllBoxPersistMode.save,
      operation: operation,
    );
  }

  Future<void> _enqueueFlush(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
    required String operation,
  }) {
    // Coalescing: if a flush is already queued (waiting behind the one
    // in-flight), don't queue another full write of a nearly identical
    // snapshot — just swap in the newer one.
    if (_pendingFlush != null) {
      _pendingSnapshot = snapshot;
      _pendingMode = _strongerMode(_pendingMode, mode);
      _pendingOperation = _mergeOperation(_pendingOperation, operation);
      return _pendingFlush!;
    }

    _pendingSnapshot = snapshot;
    _pendingMode = mode;
    _pendingOperation = operation;
    final scheduled = _flushChain.then((_) {
      final latest = _pendingSnapshot!;
      final latestMode = _pendingMode;
      final latestOperation = _pendingOperation;
      // Clear *before* the flush starts: callers arriving while it's
      // running must start a new queued flush (their data is not in
      // `latest`), whereas callers arriving before it starts were free to
      // swap `_pendingSnapshot` and ride along.
      _pendingSnapshot = null;
      _pendingFlush = null;
      _pendingMode = AllBoxPersistMode.save;
      _pendingOperation = 'flushNow';
      return _persist(latest, latestMode, latestOperation);
    });
    _pendingFlush = scheduled;
    // Keep the chain alive even if this flush fails, so later flushes still
    // wait for it instead of racing ahead.
    _flushChain = scheduled.catchError((_) {});
    return scheduled;
  }

  @override
  Future<void> close(
    Map<String, dynamic> snapshot, {
    required bool flushPending,
  }) async {
    if (_closed) return;
    if (flushPending) {
      await flushNow(snapshot);
    } else {
      _debounceTimer?.cancel();
      _dirty = false;
    }
    await _flushChain.catchError((_) {});
    _closed = true;
    await _storage.close();
  }

  @override
  Future<void> destroy(Map<String, dynamic> snapshot) async {
    if (_closed) return;
    _debounceTimer?.cancel();
    _dirty = false;
    await _flushChain.catchError((_) {});
    _closed = true;
    await _storage.delete();
    await _storage.close();
  }

  Future<void> _persist(
    Map<String, dynamic> snapshot,
    AllBoxPersistMode mode,
    String operation,
  ) async {
    flushCallCountForTesting++;
    try {
      await _storage.save(snapshot, mode: mode);
    } on Object catch (error, stackTrace) {
      onPersistenceError(operation, error, stackTrace, true);
      rethrow;
    }
  }

  static AllBoxPersistMode _strongerMode(
    AllBoxPersistMode a,
    AllBoxPersistMode b,
  ) {
    return (a == AllBoxPersistMode.flush || b == AllBoxPersistMode.flush)
        ? AllBoxPersistMode.flush
        : AllBoxPersistMode.save;
  }

  @override
  void disposeForTesting() {
    _debounceTimer?.cancel();
  }

  static String _mergeOperation(String current, String next) {
    if (current == next) return current;
    if (next == 'writeAndFlush' || current == 'writeAndFlush') {
      return 'writeAndFlush';
    }
    if (next == 'writeAndSave' || current == 'writeAndSave') {
      return 'writeAndSave';
    }
    return next;
  }
}

/// Persists every flush immediately against [_storage], with no [Timer] and
/// no debounce window at all. Used only by [AllBox.memory].
///
/// **PT-BR:** Persiste todo flush imediatamente contra o [_storage], sem
/// nenhum [Timer] e sem janela de debounce. Usado apenas pelo
/// [AllBox.memory].
class _ImmediateFlushCoordinator implements _FlushCoordinator {
  _ImmediateFlushCoordinator(this._storage);

  final AllBoxStorage _storage;
  bool _closed = false;

  @override
  int flushCallCountForTesting = 0;

  @override
  void scheduleFlush(Map<String, dynamic> snapshot) {
    if (_closed) return;
    flushCallCountForTesting++;
    // AllBoxMemoryStorage.save() has no `await` in its body, so it runs
    // fully synchronously up to completion even though it isn't awaited
    // here — see AllBoxMemoryStorage's doc comment for why that's safe.
    unawaited(
      _storage.save(
        Map<String, dynamic>.of(snapshot),
        mode: AllBoxPersistMode.flush,
      ),
    );
  }

  @override
  Future<void> flushNow(
    Map<String, dynamic> snapshot, {
    bool fsync = true,
    String operation = 'flushNow',
  }) async {
    if (_closed) {
      throw StateError('AllBox storage coordinator is closed.');
    }
    flushCallCountForTesting++;
    await _storage.save(
      Map<String, dynamic>.of(snapshot),
      mode: fsync ? AllBoxPersistMode.flush : AllBoxPersistMode.save,
    );
  }

  @override
  Future<void> close(
    Map<String, dynamic> snapshot, {
    required bool flushPending,
  }) async {
    if (_closed) return;
    if (flushPending) {
      await flushNow(snapshot);
    }
    _closed = true;
    await _storage.close();
  }

  @override
  Future<void> destroy(Map<String, dynamic> snapshot) async {
    if (_closed) return;
    _closed = true;
    await _storage.delete();
    await _storage.close();
  }

  @override
  void disposeForTesting() {}
}
