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
  /// [initialData], if non-empty, is only ever applied on a genuine first
  /// run — i.e. when `<container>.db` and `<container>.bak` do not exist
  /// yet. It seeds the container with default values (e.g. onboarding
  /// flags, default settings) so callers don't need a separate `write()`
  /// right after `init()`. It is immediately persisted to disk (bypassing
  /// the debounce window), so the seed survives a crash right after first
  /// launch. If the container was already persisted before — even as an
  /// intentionally empty `{}` written by a previous [erase] — [initialData]
  /// is ignored and whatever is on disk wins, exactly like a normal
  /// [init] call.
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
  /// [initialData], se não vazio, só é aplicado em um first-run de
  /// verdade — ou seja, quando `<container>.db` e `<container>.bak` ainda
  /// não existem. Ele popula o container com valores default (ex.: flags
  /// de onboarding, configurações padrão), evitando um `write()` separado
  /// logo após o `init()`. É persistido imediatamente em disco (ignorando
  /// a janela de debounce), então o seed sobrevive a um crash logo após o
  /// primeiro lançamento do app. Se o container já tinha sido persistido
  /// antes — mesmo que como um `{}` intencionalmente vazio escrito por um
  /// [erase] anterior — [initialData] é ignorado e o que está em disco
  /// prevalece, exatamente como em uma chamada normal de [init].
  ///
  /// Chamar [init] novamente para um container já inicializado é um no-op;
  /// o container mantém os dados que já tinha em memória.
  static Future<void> init(
    String container, {
    required String path,
    Duration flushDelay = defaultFlushDelay,
    Map<String, dynamic> initialData = const <String, dynamic>{},
  }) async {
    final box = AllBox(container);
    if (box._initialized) return;

    final io = _ContainerIO(
      container: container,
      directoryPath: path,
      flushDelay: flushDelay,
    );

    final isFirstRun = !io.hasPersistedData;
    final data = await io.readInitial();

    box._io = io;
    if (isFirstRun && initialData.isNotEmpty) {
      box._box
        ..clear()
        ..addAll(initialData);
      box._initialized = true;
      // Persist the seed right away so it isn't lost if the process dies
      // before the first real write() would have flushed it.
      await io.flushNow(box._box);
    } else {
      box._box
        ..clear()
        ..addAll(data);
      box._initialized = true;
    }
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
    _warnIfNotSerializable('write', key, value);
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
    _warnIfNotSerializable('writeAndFlush', key, value);
    _box[key] = value;
    _notifyKey(key);
    _notifyGlobal();
    await _io!.flushNow(_box);
  }

  /// Like [write], but returns a [Future] that completes once the new value
  /// has been handed to the operating system's write buffer (bypassing the
  /// debounce window) — **without** forcing an fsync.
  ///
  /// This is the intermediate durability tier, equivalent to what
  /// `Hive.put`-style APIs offer: when the [Future] completes, the data
  /// survives an app crash, but not necessarily a power loss / OS crash
  /// (the OS may still be holding it in its page cache). It keeps the full
  /// write-ahead + atomic-rename pipeline, so the container file can never
  /// be left half-written. It is orders of magnitude cheaper than
  /// [writeAndFlush], whose fsync is the only guarantee that survives
  /// power loss.
  ///
  /// Durability ladder: [write] (optimistic, debounced) → [writeAndSave]
  /// (waits for the OS write) → [writeAndFlush] (waits for fsync).
  ///
  /// **PT-BR:** Igual a [write], mas retorna um [Future] que completa
  /// quando o novo valor foi entregue ao buffer de escrita do sistema
  /// operacional (ignorando a janela de debounce) — **sem** forçar fsync.
  ///
  /// É o nível intermediário de durabilidade, equivalente ao que APIs
  /// estilo `Hive.put` oferecem: quando o [Future] completa, o dado
  /// sobrevive a um crash do app, mas não necessariamente a uma queda de
  /// energia / crash do OS (o OS ainda pode estar segurando o dado no page
  /// cache). Mantém o pipeline completo de write-ahead + rename atômico,
  /// então o arquivo do container nunca fica meio-escrito. É ordens de
  /// magnitude mais barato que [writeAndFlush], cujo fsync é a única
  /// garantia que sobrevive a queda de energia.
  ///
  /// Escada de durabilidade: [write] (otimista, debounced) →
  /// [writeAndSave] (espera o write do OS) → [writeAndFlush] (espera o
  /// fsync).
  Future<void> writeAndSave(String key, dynamic value) async {
    _assertInitialized('writeAndSave');
    _warnIfNotSerializable('writeAndSave', key, value);
    _box[key] = value;
    _notifyKey(key);
    _notifyGlobal();
    await _io!.flushNow(_box, fsync: false);
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
    if (!kDebugMode) return;
    try {
      jsonEncode(value);
    } on Object catch (error) {
      debugPrint(
        '\x1B[31mAllBox("$container").$method(\'$key\', ...): value is not '
        'JSON-encodable ($error). It was written to memory anyway, but it '
        'will silently fail to reach disk. All values must be '
        'JSON-encodable (String, num, bool, null, List, Map, or an object '
        'with a toJson() that returns one of those).\x1B[0m',
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
  Future<void> flushNow(Map<String, dynamic> snapshot, {bool fsync});
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

  /// Whether this container has ever actually been flushed to disk before,
  /// i.e. whether [_dbFile] or [_bakFile] already exists. Checked
  /// synchronously, on purpose: it must be read before [readInitial] has any
  /// chance to create the directory or touch either file, so it reflects
  /// the state exactly as [AllBox.init] found it.
  ///
  /// Used by [AllBox.init] to decide whether an `initialData` seed should
  /// be applied. A seed is only ever written on a genuine first run — never
  /// re-applied over legitimately-persisted data, including an
  /// intentionally empty container left behind by a previous [AllBox.erase]
  /// (which still writes a `{}` file, so this returns `true` for it).
  ///
  /// **PT-BR:** Se este container já foi de fato gravado em disco alguma
  /// vez, ou seja, se [_dbFile] ou [_bakFile] já existem. Verificado de
  /// forma síncrona, de propósito: precisa ser lido antes de [readInitial]
  /// ter qualquer chance de criar o diretório ou tocar em algum dos
  /// arquivos, para refletir o estado exatamente como o [AllBox.init]
  /// encontrou.
  ///
  /// Usado pelo [AllBox.init] para decidir se um seed de `initialData` deve
  /// ser aplicado. Um seed só é gravado em um first-run de verdade — nunca
  /// reaplicado sobre dado legitimamente persistido, incluindo um container
  /// intencionalmente vazio deixado por um [AllBox.erase] anterior (que
  /// ainda assim escreve um arquivo `{}`, então isso retorna `true` para
  /// esse caso).
  bool get hasPersistedData => _dbFile.existsSync() || _bakFile.existsSync();

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

  /// Schedules a coalesced flush: the first write of a burst arms a single
  /// [Timer]; every subsequent write within [flushDelay] just marks the
  /// container dirty and rides on the already-armed timer, so a burst still
  /// produces exactly one flush.
  ///
  /// Two deliberate consequences of NOT re-arming the timer per write
  /// (which is what a classic debounce would do):
  ///  1. Performance — `Timer.cancel()` + `Timer()` per write used to cost
  ///     more than the actual in-memory map update, dominating `write()`'s
  ///     hot path. Now a burst pays for one timer, total.
  ///  2. No starvation — the flush happens at most [flushDelay] after the
  ///     *first* write of a burst, even under continuous writes (e.g. a
  ///     slider emitting every frame), instead of being pushed forever
  ///     into the future. The timer callback copies the live map at fire
  ///     time, so everything written during the window is included.
  ///
  /// **PT-BR:** Agenda um flush coalescido: a primeira escrita de um burst
  /// arma um único [Timer]; cada escrita seguinte dentro de [flushDelay]
  /// só marca o container como sujo e pega carona no timer já armado —
  /// um burst continua produzindo exatamente um flush.
  ///
  /// Duas consequências deliberadas de NÃO rearmar o timer a cada escrita
  /// (que é o que um debounce clássico faria):
  ///  1. Performance — `Timer.cancel()` + `Timer()` por escrita custava
  ///     mais que a própria atualização do map em memória, dominando o hot
  ///     path do `write()`. Agora um burst paga um timer, no total.
  ///  2. Sem starvation — o flush acontece no máximo [flushDelay] depois
  ///     da *primeira* escrita do burst, mesmo sob escrita contínua (ex.:
  ///     um slider emitindo a cada frame), em vez de ser empurrado para
  ///     sempre. O callback do timer copia o map vivo na hora de disparar,
  ///     então tudo que foi escrito durante a janela é incluído.
  @override
  void scheduleFlush(Map<String, dynamic> snapshot) {
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
      // — e.g. a real disk error such as running out of space or a
      // permission problem (non-JSON-encodable values are already rejected
      // synchronously in AllBox.write/writeAndFlush, before they ever reach
      // here) — must not become an unhandled Future error. Callers using
      // writeAndFlush()/flushNow() still see failures normally, since they
      // await _enqueueFlush's result directly.
      unawaited(
        _enqueueFlush(Map<String, dynamic>.of(snapshot), fsync: true)
            .catchError((
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
  Future<void> flushNow(Map<String, dynamic> snapshot, {bool fsync = true}) {
    _debounceTimer?.cancel();
    _dirty = false;
    return _enqueueFlush(Map<String, dynamic>.of(snapshot), fsync: fsync);
  }

  /// Snapshot waiting to be written by the next queued flush. While a flush
  /// is queued (but not yet running), every new flush request simply
  /// replaces this snapshot instead of enqueuing another full disk write —
  /// each snapshot is a copy of the *entire* box taken after the caller's
  /// write, so the newest one always contains every previous caller's data.
  ///
  /// **PT-BR:** Snapshot aguardando o próximo flush enfileirado. Enquanto um
  /// flush está na fila (mas ainda não rodando), cada novo pedido de flush
  /// apenas substitui este snapshot em vez de enfileirar outra gravação
  /// completa — cada snapshot é uma cópia do box *inteiro* tirada depois do
  /// write do caller, então o mais novo sempre contém os dados de todos os
  /// callers anteriores.
  Map<String, dynamic>? _pendingSnapshot;

  /// The [Future] shared by every caller coalesced into the next queued
  /// flush. Completes only after the (single) disk write that covers all of
  /// them has finished, so `writeAndFlush`'s contract — "my value is on
  /// disk when this completes" — still holds for each caller.
  ///
  /// **PT-BR:** O [Future] compartilhado por todos os callers coalescidos no
  /// próximo flush enfileirado. Só completa depois que a (única) gravação em
  /// disco que cobre todos eles terminar, então o contrato do
  /// `writeAndFlush` — "meu valor está em disco quando isto completar" —
  /// continua valendo para cada caller.
  Future<void>? _pendingFlush;

  /// Whether the queued flush must fsync. When callers with different
  /// durability levels coalesce into the same disk write, the strongest
  /// requirement wins: one `writeAndFlush` among ten `writeAndSave`s makes
  /// the shared flush fsync.
  ///
  /// **PT-BR:** Se o flush enfileirado precisa de fsync. Quando callers com
  /// níveis diferentes de durabilidade coalescem na mesma gravação, o
  /// requisito mais forte vence: um `writeAndFlush` entre dez
  /// `writeAndSave` faz o flush compartilhado ter fsync.
  bool _pendingFsync = false;

  Future<void> _enqueueFlush(
    Map<String, dynamic> snapshot, {
    required bool fsync,
  }) {
    // Coalescing: if a flush is already queued (waiting behind the one
    // in-flight), don't queue another full write of a nearly identical
    // snapshot — just swap in the newer one. N concurrent writeAndFlush()
    // calls collapse into at most one in-flight write plus one queued write,
    // instead of N sequential full-file writes.
    //
    // **PT-BR:** Coalescing: se já existe um flush na fila (esperando atrás
    // do que está em andamento), não enfileira outra gravação completa de um
    // snapshot quase idêntico — só troca pelo mais novo. N chamadas
    // concorrentes de writeAndFlush() colapsam em no máximo uma gravação em
    // andamento mais uma na fila, em vez de N gravações completas em série.
    if (_pendingFlush != null) {
      _pendingSnapshot = snapshot;
      _pendingFsync = _pendingFsync || fsync;
      return _pendingFlush!;
    }

    _pendingSnapshot = snapshot;
    _pendingFsync = fsync;
    final scheduled = _flushChain.then((_) {
      final latest = _pendingSnapshot!;
      final latestFsync = _pendingFsync;
      // Clear *before* the disk write starts: callers arriving while the
      // write is running must start a new queued flush (their data is not
      // in `latest`), whereas callers arriving before it starts were free
      // to swap `_pendingSnapshot` and ride along.
      //
      // **PT-BR:** Limpa *antes* da gravação começar: callers que chegarem
      // durante a gravação precisam iniciar um novo flush na fila (os dados
      // deles não estão em `latest`), enquanto os que chegaram antes dela
      // começar puderam trocar o `_pendingSnapshot` e pegar carona.
      _pendingSnapshot = null;
      _pendingFlush = null;
      _pendingFsync = false;
      return _writeToDisk(latest, fsync: latestFsync);
    });
    _pendingFlush = scheduled;
    // Keep the chain alive even if this flush fails, so later flushes still
    // wait for it instead of racing ahead.
    _flushChain = scheduled.catchError((_) {});
    return scheduled;
  }

  Future<void> _writeToDisk(
    Map<String, dynamic> snapshot, {
    required bool fsync,
  }) async {
    flushCallCountForTesting++;
    final jsonText = jsonEncode(snapshot);

    // 1) Write-ahead: new content always lands on a temp file first. If the
    //    process dies during this write, `container.db` is untouched.
    //    `flush: fsync` is what separates the two durability tiers:
    //    `writeAndFlush`/`flushNow` fsync (survives power loss);
    //    `writeAndSave` only waits for the OS write (survives an app
    //    crash, like Hive's `put`), which is orders of magnitude cheaper.
    //
    //    **PT-BR:** `flush: fsync` é o que separa os dois níveis de
    //    durabilidade: `writeAndFlush`/`flushNow` fazem fsync (sobrevive a
    //    queda de energia); `writeAndSave` só espera o write do OS
    //    (sobrevive a crash do app, como o `put` do Hive), que é ordens de
    //    magnitude mais barato.
    await _tmpFile.writeAsString(jsonText, flush: fsync);

    // 2) Preserve the last known-good file as a backup before replacing it.
    //    A rename is a metadata-only operation (no bytes are copied), unlike
    //    the full byte-for-byte `copy` used previously — this alone removes
    //    roughly half of the I/O of every flush. Crash-safety is unchanged:
    //    at any instant either `.db` or `.bak` holds a complete, known-good
    //    version, and `readInitial` already falls back to `.bak` when `.db`
    //    is missing or unreadable. Dart's `File.rename` replaces an existing
    //    destination on every platform, including Windows.
    //
    //    **PT-BR:** Preserva o último arquivo íntegro como backup antes de
    //    substituí-lo. `rename` é operação só de metadata (nenhum byte é
    //    copiado), ao contrário do `copy` byte a byte usado antes — só isso
    //    já remove cerca de metade do I/O de cada flush. A crash-safety não
    //    muda: a qualquer instante `.db` ou `.bak` contém uma versão íntegra,
    //    e o `readInitial` já cai pro `.bak` quando o `.db` está ausente ou
    //    ilegível. O `File.rename` do Dart sobrescreve destino existente em
    //    todas as plataformas, inclusive Windows.
    if (_dbFile.existsSync()) {
      try {
        await _dbFile.rename(_bakFile.path);
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
  Future<void> flushNow(Map<String, dynamic> snapshot, {bool fsync = true}) async {
    flushCallCountForTesting++;
    _lastSnapshot = Map<String, dynamic>.of(snapshot);
  }

  @override
  void disposeForTesting() {}
}
