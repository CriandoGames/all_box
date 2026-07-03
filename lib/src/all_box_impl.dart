import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// A synchronous, lightweight key-value storage container.
///
/// `AllBox` keeps all data in memory (in a `Map<String, dynamic>`), so every
/// read (`read`, `readOrDefault`, `hasData`, `getKeys`, `getValues`) is
/// synchronous and never touches the disk. Writes are optimistic: `write()`
/// updates memory and notifies listeners immediately; persisting to disk
/// happens asynchronously afterwards, debounced so that bursts of writes
/// generate a single flush.
///
/// One physical file is used per *container* (a logical name), not one file
/// per key. `AllBox` never resolves its own storage directory — the caller
/// must always provide a `path` to [init], keeping this package free of any
/// `path_provider` dependency (and the `MissingPluginException` issues that
/// come with resolving platform channels too early).
///
/// **PT-BR:** Um storage key-value síncrono e leve.
///
/// O `AllBox` mantém todos os dados em memória (em um `Map<String,
/// dynamic>`), então toda leitura (`read`, `readOrDefault`, `hasData`,
/// `getKeys`, `getValues`) é síncrona e nunca toca o disco. As escritas são
/// otimistas: `write()` atualiza a memória e notifica os listeners
/// imediatamente; a persistência em disco acontece depois, de forma
/// assíncrona e com debounce, para que várias escritas seguidas gerem um
/// único flush.
///
/// Um arquivo físico é usado por *container* (um nome lógico), não um
/// arquivo por chave. O `AllBox` nunca resolve seu próprio diretório de
/// armazenamento — quem chama deve sempre fornecer um `path` para [init],
/// mantendo este pacote livre de qualquer dependência de `path_provider`
/// (e dos problemas de `MissingPluginException` que vêm de resolver canais
/// de plataforma cedo demais).
class AllBox {
  factory AllBox([String container = defaultContainerName]) {
    return _instances.putIfAbsent(container, () => AllBox._internal(container));
  }

  AllBox._internal(this.container);

  /// The container name used when none is supplied.
  ///
  /// **PT-BR:** Nome do container usado quando nenhum é informado.
  static const String defaultContainerName = 'AllBox';

  /// Default debounce window used to coalesce successive [write] calls into
  /// a single disk flush. Configurable per container via [init].
  ///
  /// **PT-BR:** Janela de debounce padrão usada para agrupar chamadas
  /// sucessivas de [write] em um único flush em disco. Configurável por
  /// container via [init].
  static const Duration defaultFlushDelay = Duration(milliseconds: 100);

  /// The logical name of this container. Each container is persisted to its
  /// own file (`<container>.db`) inside the directory passed to [init].
  ///
  /// **PT-BR:** Nome lógico deste container. Cada container é persistido em
  /// seu próprio arquivo (`<container>.db`) dentro do diretório passado
  /// para [init].
  final String container;

  static final Map<String, AllBox> _instances = <String, AllBox>{};

  /// In-memory, synchronously-readable data for this container.
  ///
  /// **PT-BR:** Dados em memória deste container, lidos de forma síncrona.
  final Map<String, dynamic> _box = <String, dynamic>{};

  final Map<String, List<VoidCallback>> _keyListeners =
      <String, List<VoidCallback>>{};
  final List<VoidCallback> _globalListeners = <VoidCallback>[];

  _IOBackend? _io;
  bool _initialized = false;

  /// Whether [init] has already completed for this container.
  ///
  /// **PT-BR:** Se [init] já foi concluído para este container.
  bool get isInitialized => _initialized;

  /// Initializes [container], loading its data from disk (if any) into
  /// memory so that subsequent reads are synchronous.
  ///
  /// [path] is the directory where `<container>.db` (and its `.tmp`/`.bak`
  /// companions) live. Resolving this path (e.g. via `path_provider`,
  /// `getApplicationDocumentsDirectory`, or any other means) is entirely the
  /// caller's responsibility — `AllBox` deliberately never does this itself.
  ///
  /// Calling [init] again for a container that is already initialized is a
  /// no-op; the container keeps whatever data it currently holds in memory.
  ///
  /// **PT-BR:** Inicializa [container], carregando os dados do disco (se
  /// existirem) para a memória, para que as leituras seguintes sejam
  /// síncronas.
  ///
  /// [path] é o diretório onde `<container>.db` (e seus companheiros
  /// `.tmp`/`.bak`) ficam. Resolver esse path (via `path_provider`,
  /// `getApplicationDocumentsDirectory`, ou qualquer outro meio) é
  /// responsabilidade inteiramente de quem chama — o `AllBox`
  /// deliberadamente nunca faz isso sozinho.
  ///
  /// Chamar [init] novamente para um container já inicializado é um no-op;
  /// o container mantém os dados que já tinha em memória.
  static Future<void> init(
    String container, {
    required String path,
    Duration flushDelay = defaultFlushDelay,
  }) async {
    final box = AllBox(container);
    if (box._initialized) return;

    final io = _ContainerIO(
      container: container,
      directoryPath: path,
      flushDelay: flushDelay,
    );
    final data = await io.readInitial();

    box._io = io;
    box._box
      ..clear()
      ..addAll(data);
    box._initialized = true;
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
  /// This is optimistic: the in-memory map is updated and listeners
  /// (`listenKey`/`listenAll`) are notified synchronously, before this
  /// method returns. The disk write is scheduled asynchronously and
  /// debounced — several `write()` calls in quick succession result in a
  /// single flush to disk.
  ///
  /// **PT-BR:** Escreve [value] em [key].
  ///
  /// Isso é otimista: o mapa em memória é atualizado e os listeners
  /// (`listenKey`/`listenAll`) são notificados de forma síncrona, antes
  /// deste método retornar. A escrita em disco é agendada de forma
  /// assíncrona e com debounce — várias chamadas de `write()` em sequência
  /// rápida resultam em um único flush em disco.
  void write(String key, dynamic value) {
    _assertInitialized('write');
    _assertSerializable('write', key, value);
    _box[key] = value;
    _notifyKey(key);
    _notifyGlobal();
    _io!.scheduleFlush(_box);
  }

  /// Like [write], but returns a [Future] that only completes once the new
  /// value has actually been persisted to disk (bypassing the debounce
  /// window).
  ///
  /// **PT-BR:** Igual a [write], mas retorna um [Future] que só completa
  /// quando o novo valor tiver sido de fato persistido em disco
  /// (ignorando a janela de debounce).
  Future<void> writeAndFlush(String key, dynamic value) async {
    _assertInitialized('writeAndFlush');
    _assertSerializable('writeAndFlush', key, value);
    _box[key] = value;
    _notifyKey(key);
    _notifyGlobal();
    await _io!.flushNow(_box);
  }

  /// Removes [key], notifying its listeners if it was present.
  ///
  /// **PT-BR:** Remove [key], notificando seus listeners se ela existia.
  void remove(String key) {
    _assertInitialized('remove');
    if (!_box.containsKey(key)) return;
    _box.remove(key);
    _notifyKey(key);
    _notifyGlobal();
    _io!.scheduleFlush(_box);
  }

  /// Clears every key in this container, notifying the listeners of every
  /// key that existed *before* the container was cleared (as well as the
  /// global listeners).
  ///
  /// **PT-BR:** Limpa todas as chaves deste container, notificando os
  /// listeners de cada chave que existia *antes* do container ser limpo
  /// (assim como os listeners globais).
  void erase() {
    _assertInitialized('erase');
    final keysBefore = List<String>.of(_box.keys);
    _box.clear();
    for (final key in keysBefore) {
      _notifyKey(key);
    }
    _notifyGlobal();
    _io!.scheduleFlush(_box);
  }

  /// Forces an immediate flush to disk, ignoring the debounce window.
  ///
  /// Intended to be called e.g. from `AppLifecycleState.paused`, to make
  /// sure nothing pending is lost if the process is about to be killed.
  ///
  /// **PT-BR:** Força um flush imediato em disco, ignorando a janela de
  /// debounce.
  ///
  /// Feito para ser chamado, por exemplo, a partir de
  /// `AppLifecycleState.paused`, para garantir que nada pendente se perca
  /// caso o processo seja finalizado.
  Future<void> flushNow() async {
    _assertInitialized('flushNow');
    await _io!.flushNow(_box);
  }

  /// Registers [callback] to be invoked whenever [key] is written to or
  /// removed (including via [erase]).
  ///
  /// **PT-BR:** Registra [callback] para ser chamado sempre que [key] for
  /// escrita ou removida (inclusive via [erase]).
  void listenKey(String key, VoidCallback callback) {
    _keyListeners.putIfAbsent(key, () => <VoidCallback>[]).add(callback);
  }

  /// Removes a callback previously registered with [listenKey].
  ///
  /// **PT-BR:** Remove um callback previamente registrado com [listenKey].
  void removeListenKey(String key, VoidCallback callback) {
    final listeners = _keyListeners[key];
    if (listeners == null) return;
    listeners.remove(callback);
    if (listeners.isEmpty) _keyListeners.remove(key);
  }

  /// Registers [callback] to be invoked on every mutation of this container
  /// (`write`, `remove`, `erase`), regardless of key.
  ///
  /// Returns a [VoidCallback] that removes the listener, e.g.:
  /// ```dart
  /// final dispose = box.listenAll(() => print('mudou'));
  /// // later
  /// dispose();
  /// ```
  ///
  /// **PT-BR:** Registra [callback] para ser chamado a cada mutação deste
  /// container (`write`, `remove`, `erase`), independente da chave.
  ///
  /// Retorna um [VoidCallback] que remove o listener, por exemplo:
  /// ```dart
  /// final dispose = box.listenAll(() => print('mudou'));
  /// // depois
  /// dispose();
  /// ```
  VoidCallback listenAll(VoidCallback callback) {
    _globalListeners.add(callback);
    return () => _globalListeners.remove(callback);
  }

  void _notifyKey(String key) {
    final listeners = _keyListeners[key];
    if (listeners == null || listeners.isEmpty) return;
    for (final callback in List<VoidCallback>.of(listeners)) {
      callback();
    }
  }

  void _notifyGlobal() {
    if (_globalListeners.isEmpty) return;
    for (final callback in List<VoidCallback>.of(_globalListeners)) {
      callback();
    }
  }

  void _assertInitialized(String method) {
    if (!_initialized || _io == null) {
      throw StateError(
        'AllBox("$container").$method() called before initialization. '
        "Call `await AllBox.init('$container', path: yourDirectoryPath)` "
        'first (for example in `main()`, after '
        '`WidgetsFlutterBinding.ensureInitialized()`).',
      );
    }
  }

  /// Fails fast, synchronously, if [value] is not JSON-encodable.
  ///
  /// Without this, a non-encodable value (e.g. a `DateTime`, a custom class
  /// with no `toJson()`, a cyclic structure) would only be discovered later,
  /// inside the debounced flush — which is fire-and-forget by design, so the
  /// failure would just become a silent `debugPrint` and the value would
  /// never actually reach disk. Failing here, in the same call stack as
  /// [write]/[writeAndFlush], turns that into an immediate, loud error
  /// instead.
  ///
  /// **PT-BR:** Falha rápido, de forma síncrona, se [value] não for
  /// JSON-encodável.
  ///
  /// Sem isso, um valor não serializável (ex.: um `DateTime`, uma classe
  /// própria sem `toJson()`, uma estrutura cíclica) só seria descoberto
  /// depois, dentro do flush debounced — que é fire-and-forget por design,
  /// então a falha viraria só um `debugPrint` silencioso e o valor nunca
  /// chegaria de fato ao disco. Falhar aqui, na mesma call stack de
  /// [write]/[writeAndFlush], transforma isso em um erro imediato e visível.
  void _assertSerializable(String method, String key, dynamic value) {
    try {
      jsonEncode(value);
    } on Object catch (error) {
      throw ArgumentError.value(
        value,
        'value',
        'AllBox("$container").$method(\'$key\', ...): value is not '
            'JSON-encodable ($error). All values must be JSON-encodable '
            '(String, num, bool, null, List, Map, or an object with a '
            'toJson() that returns one of those).',
      );
    }
  }

  /// Removes this container's cached singleton instance and cancels any
  /// pending debounce timer, without touching whatever was already flushed
  /// to disk. Intended for tests; not part of the stable public API.
  ///
  /// **PT-BR:** Remove a instância singleton em cache deste container e
  /// cancela qualquer timer de debounce pendente, sem tocar no que já foi
  /// gravado em disco. Feito para testes; não faz parte da API pública
  /// estável.
  @visibleForTesting
  static void resetInstanceForTesting(String container) {
    final box = _instances.remove(container);
    box?._io?.disposeForTesting();
  }

  /// Number of times this container has actually flushed to disk since
  /// [init]. Intended for tests that need a deterministic way to assert on
  /// debounce behavior, instead of watching the filesystem for
  /// notifications (unreliable on Windows). Not part of the stable public
  /// API.
  ///
  /// **PT-BR:** Quantidade de vezes que este container de fato gravou em
  /// disco desde o [init]. Feito para testes que precisam de uma forma
  /// determinística de verificar o comportamento de debounce, em vez de
  /// observar o sistema de arquivos por notificações (instável no
  /// Windows). Não faz parte da API pública estável.
  @visibleForTesting
  int get flushCountForTesting => _io?.flushCallCountForTesting ?? 0;

  /// Initializes [container] with a pure in-memory backend: no real disk
  /// I/O, no real [Timer], no temp directory required. Every [write] is
  /// "flushed" synchronously into an in-memory snapshot instead of a debounce
  /// window.
  ///
  /// Intended for apps/packages that *consume* `all_box` and want to
  /// unit/widget-test their own code against a real [AllBox] instance,
  /// without the flakiness or setup cost of real filesystem access. It is
  /// also what removes the only source of a real, pending `Timer` that a
  /// normal [init] would
  /// otherwise schedule on the first [write] — which matters specifically
  /// inside `testWidgets`, since its `FakeAsync` zone expects every `Timer`
  /// to resolve before the test ends; a real one left pending there can hang
  /// the test runner instead of failing it.
  ///
  /// Not part of the stable public API — this is a testing utility, not a
  /// second production backend.
  ///
  /// **PT-BR:** Inicializa [container] com um backend puramente em memória:
  /// sem I/O real em disco, sem [Timer] real, sem precisar de diretório
  /// temporário. Todo [write] é "flushado" de forma síncrona em um snapshot
  /// em memória, em vez de uma janela de debounce.
  ///
  /// Feito para apps/pacotes que *consomem* o `all_box` e querem testar
  /// (unit/widget) o próprio código contra uma instância real de [AllBox],
  /// sem o custo/flakiness de acesso real ao sistema de arquivos. É também
  /// o que elimina a única fonte de um `Timer` real pendente que um [init]
  /// normal agendaria
  /// no primeiro [write] — o que importa especificamente dentro de
  /// `testWidgets`, já que sua zona `FakeAsync` espera que todo `Timer`
  /// seja resolvido antes do teste terminar; um real deixado pendente ali
  /// pode travar o test runner em vez de falhar o teste.
  ///
  /// Não faz parte da API pública estável — é um utilitário de teste, não
  /// um segundo backend de produção.
  @visibleForTesting
  static Future<void> initWithMemoryBackendForTesting(
    String container, {
    Map<String, dynamic> initialValues = const <String, dynamic>{},
  }) async {
    final box = AllBox(container);
    if (box._initialized) return;

    box._io = _InMemoryIO();
    box._box
      ..clear()
      ..addAll(initialValues);
    box._initialized = true;
  }
}

/// Internal seam between [AllBox] and however a container is actually
/// persisted. [_ContainerIO] is the real, disk-backed implementation used by
/// [AllBox.init]; [_InMemoryIO] is a fake used only by
/// [AllBox.initWithMemoryBackendForTesting]. Not exported.
///
/// **PT-BR:** Costura interna entre [AllBox] e a forma como um container é
/// de fato persistido. [_ContainerIO] é a implementação real, baseada em
/// disco, usada por [AllBox.init]; [_InMemoryIO] é uma falsa usada apenas
/// por [AllBox.initWithMemoryBackendForTesting]. Não é exportada.
abstract class _IOBackend {
  Future<Map<String, dynamic>> readInitial();
  void scheduleFlush(Map<String, dynamic> snapshot);
  Future<void> flushNow(Map<String, dynamic> snapshot);
  void disposeForTesting();
  int get flushCallCountForTesting;
}

/// Handles all filesystem concerns for a single container: the write-ahead
/// temp file, the atomic rename, the `.bak` fallback, the debounce timer and
/// the serialized flush queue. Not exported — purely an implementation
/// detail of [AllBox].
///
/// **PT-BR:** Cuida de tudo relacionado ao sistema de arquivos para um
/// container: o arquivo temporário write-ahead, o rename atômico, o
/// fallback `.bak`, o timer de debounce e a fila de flush serializada. Não
/// é exportada — é puramente um detalhe de implementação do [AllBox].
class _ContainerIO implements _IOBackend {
  _ContainerIO({
    required this.container,
    required String directoryPath,
    required this.flushDelay,
  }) : _directory = Directory(directoryPath);

  final String container;
  final Directory _directory;
  final Duration flushDelay;

  Timer? _debounceTimer;
  bool _dirty = false;

  /// Number of times [_writeToDisk] actually ran. Only incremented for
  /// tests — counting real disk flushes this way is deterministic across
  /// platforms, unlike watching the filesystem for notifications (which is
  /// notoriously unreliable on Windows: events can be dropped, coalesced or
  /// delayed — see dart-lang/sdk#37233).
  ///
  /// **PT-BR:** Quantidade de vezes que [_writeToDisk] de fato rodou. Só é
  /// incrementado para testes — contar flushes reais dessa forma é
  /// determinístico em qualquer plataforma, ao contrário de observar o
  /// sistema de arquivos por notificações (notoriamente instável no
  /// Windows: eventos podem ser perdidos, agrupados ou atrasados — veja
  /// dart-lang/sdk#37233).
  @override
  int flushCallCountForTesting = 0;

  /// Chain used to serialize flushes: a new flush is only started after the
  /// previous one (successful or not) has finished, so two `writeAsString`
  /// calls never race on the same file.
  ///
  /// **PT-BR:** Cadeia usada para serializar os flushes: um novo flush só
  /// começa depois que o anterior (com sucesso ou não) tiver terminado, de
  /// forma que duas chamadas de `writeAsString` nunca concorram no mesmo
  /// arquivo.
  Future<void> _flushChain = Future<void>.value();

  File get _dbFile =>
      File('${_directory.path}${Platform.pathSeparator}$container.db');

  File get _tmpFile =>
      File('${_directory.path}${Platform.pathSeparator}$container.tmp');

  File get _bakFile =>
      File('${_directory.path}${Platform.pathSeparator}$container.bak');

  /// Loads the initial data for this container, trying the main file first
  /// and falling back to the backup file. Never throws: any failure results
  /// in an empty container instead of crashing the caller.
  ///
  /// **PT-BR:** Carrega os dados iniciais deste container, tentando
  /// primeiro o arquivo principal e recorrendo ao arquivo de backup em
  /// seguida. Nunca lança exceção: qualquer falha resulta em um container
  /// vazio, em vez de derrubar quem chamou.
  @override
  Future<Map<String, dynamic>> readInitial() async {
    if (!_directory.existsSync()) {
      await _directory.create(recursive: true);
    }

    final fromMain = await _tryRead(_dbFile);
    if (fromMain != null) return fromMain;

    final fromBackup = await _tryRead(_bakFile);
    if (fromBackup != null) return fromBackup;

    // Neither the main file nor the backup could be read (missing, binary
    // garbage, truncated JSON, ...): start with an empty container rather
    // than crashing the app.
    return <String, dynamic>{};
  }

  /// Attempts to read and decode [file], returning `null` on *any* failure
  /// so the caller can fall back to the next candidate.
  ///
  /// This is split into two explicit stages, matching two different classes
  /// of on-disk corruption:
  ///  1. UTF-8 decoding of the raw bytes (thrown when the file contains
  ///     binary/garbage bytes that are not valid UTF-8 at all).
  ///  2. JSON parsing of the resulting text (thrown when the bytes are
  ///     valid text but not valid JSON, e.g. a partially-written file from
  ///     a process that died mid write, before write-ahead was in place).
  ///
  /// **PT-BR:** Tenta ler e decodificar [file], retornando `null` em
  /// *qualquer* falha, para que quem chamou possa recorrer ao próximo
  /// candidato.
  ///
  /// Isso é dividido em dois estágios explícitos, cada um correspondendo a
  /// uma classe diferente de corrupção em disco:
  ///  1. Decodificação UTF-8 dos bytes brutos (lançada quando o arquivo
  ///     contém bytes binários/lixo que não são UTF-8 válido).
  ///  2. Parsing de JSON do texto resultante (lançado quando os bytes são
  ///     texto válido mas não JSON válido, ex.: um arquivo parcialmente
  ///     escrito por um processo que morreu no meio da gravação, antes do
  ///     write-ahead existir).
  Future<Map<String, dynamic>?> _tryRead(File file) async {
    if (!file.existsSync()) return null;

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }

    // Stage 1: UTF-8 decoding.
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return null;
    }

    // Stage 2: JSON parsing.
    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map<dynamic, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  /// Schedules a debounced flush: if called again before [flushDelay]
  /// elapses, the timer is reset and only a single flush eventually runs.
  ///
  /// **PT-BR:** Agenda um flush com debounce: se chamado novamente antes
  /// de [flushDelay] decorrer, o timer é reiniciado e, no fim, apenas um
  /// flush é executado.
  @override
  void scheduleFlush(Map<String, dynamic> snapshot) {
    _dirty = true;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(flushDelay, () {
      if (!_dirty) return;
      _dirty = false;
      // This flush is fire-and-forget (nobody awaits it), so a failure here
      // — e.g. a real disk error such as running out of space or a
      // permission problem (non-JSON-encodable values are already rejected
      // synchronously in AllBox.write/writeAndFlush, before they ever reach
      // here) — must not become an unhandled Future error. Callers using
      // writeAndFlush()/flushNow() still see failures normally, since they
      // await _enqueueFlush's result directly.
      unawaited(
        _enqueueFlush(Map<String, dynamic>.of(snapshot)).catchError((
          Object error,
          StackTrace stackTrace,
        ) {
          debugPrint(
            'AllBox("$container"): debounced flush failed and was '
            'dropped: $error',
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
  Future<void> flushNow(Map<String, dynamic> snapshot) {
    _debounceTimer?.cancel();
    _dirty = false;
    return _enqueueFlush(Map<String, dynamic>.of(snapshot));
  }

  Future<void> _enqueueFlush(Map<String, dynamic> snapshot) {
    final scheduled = _flushChain.then((_) => _writeToDisk(snapshot));
    // Keep the chain alive even if this flush fails, so later flushes still
    // wait for it instead of racing ahead.
    _flushChain = scheduled.catchError((_) {});
    return scheduled;
  }

  Future<void> _writeToDisk(Map<String, dynamic> snapshot) async {
    flushCallCountForTesting++;
    final jsonText = jsonEncode(snapshot);

    // 1) Write-ahead: new content always lands on a temp file first. If the
    //    process dies during this write, `container.db` is untouched.
    await _tmpFile.writeAsString(jsonText, flush: true);

    // 2) Preserve the last known-good file as a backup before replacing it.
    if (_dbFile.existsSync()) {
      try {
        await _dbFile.copy(_bakFile.path);
      } catch (_) {
        // Best-effort: a failed backup refresh must not block the swap.
      }
    }

    // 3) Atomic swap. A rename is a single filesystem operation: the main
    //    file is either fully the previous version or fully the new one,
    //    never a half-written file.
    await _tmpFile.rename(_dbFile.path);
  }

  @override
  void disposeForTesting() {
    _debounceTimer?.cancel();
  }
}

/// Pure in-memory [_IOBackend] used only by
/// [AllBox.initWithMemoryBackendForTesting]. Does no real disk I/O and
/// schedules no real [Timer] — every write is "flushed" synchronously into
/// an in-memory snapshot.
///
/// **PT-BR:** [_IOBackend] puramente em memória, usado apenas por
/// [AllBox.initWithMemoryBackendForTesting]. Não faz I/O real em disco e
/// não agenda nenhum [Timer] real — todo write é "flushado" de forma
/// síncrona em um snapshot em memória.
class _InMemoryIO implements _IOBackend {
  Map<String, dynamic> _lastSnapshot = <String, dynamic>{};

  @override
  int flushCallCountForTesting = 0;

  @override
  Future<Map<String, dynamic>> readInitial() async {
    return Map<String, dynamic>.of(_lastSnapshot);
  }

  @override
  void scheduleFlush(Map<String, dynamic> snapshot) {
    flushCallCountForTesting++;
    _lastSnapshot = Map<String, dynamic>.of(snapshot);
  }

  @override
  Future<void> flushNow(Map<String, dynamic> snapshot) async {
    flushCallCountForTesting++;
    _lastSnapshot = Map<String, dynamic>.of(snapshot);
  }

  @override
  void disposeForTesting() {}
}
