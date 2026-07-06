// On-device storage benchmark: all_box vs GetStorage vs Hive vs
// SharedPreferences, all running the SAME loops on the SAME device in the
// SAME session — the only comparison methodology that produces publishable
// numbers.
//
// Fairness notes (also shown in the UI):
//  - "Durable write" means different things per lib: `all_box` fsyncs on
//    every writeAndFlush(); Hive appends to its log WITHOUT fsync;
//    GetStorage rewrites its file without fsync; SharedPreferences goes
//    through a platform channel. Same loop, but different guarantees —
//    that's the point of showing it.
//  - Run in profile/release (`flutter run --profile`) for publishable
//    numbers: debug mode inflates everything (all_box additionally pays a
//    debug-only jsonEncode guard on every write).
//
// **PT-BR:** Benchmark de storage no dispositivo: all_box vs GetStorage vs
// Hive vs SharedPreferences, todos rodando os MESMOS loops no MESMO
// dispositivo na MESMA sessão — a única metodologia que produz números
// publicáveis.
//
// Notas de justiça (também mostradas na UI):
//  - "Escrita durável" significa coisas diferentes por lib: `all_box` faz
//    fsync em todo writeAndFlush(); Hive anexa no log SEM fsync; GetStorage
//    regrava o arquivo sem fsync; SharedPreferences passa por platform
//    channel. Mesmo loop, garantias diferentes — mostrar isso é o objetivo.
//  - Rode em profile/release (`flutter run --profile`) para números
//    publicáveis: debug infla tudo (o all_box ainda paga um guard de
//    jsonEncode só-de-debug em cada write).

import 'dart:async';

import 'package:all_box/all_box.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ops per scenario. Memory scenarios use many ops because a single pass
/// of 1.000 ops finishes in under 1ms — below the stopwatch's noise floor,
/// which made sub-µs rankings shuffle between runs. Durable writes are far
/// slower (real disk round trip per op), so they run fewer iterations.
///
/// **PT-BR:** Ops por cenário. Os cenários de memória usam muitas ops
/// porque uma única passada de 1.000 ops termina em menos de 1ms — abaixo
/// do piso de ruído do cronômetro, o que fazia rankings sub-µs
/// embaralharem entre execuções. Escritas duráveis são bem mais lentas
/// (ida real ao disco por op), então rodam menos iterações.
const int kMemoryOps = 10000;
const int kDurableOps = 200;

/// Each scenario runs multiple rounds and reports the MEDIAN, killing
/// one-off outliers (GC pause, thermal throttling, background I/O).
const int kMemoryRounds = 5;
const int kDurableRounds = 3;

enum Scenario {
  optimisticWrite('Escrita otimista (memória)', kMemoryOps),
  syncRead('Leitura síncrona', kMemoryOps),
  confirmedWrite('Escrita confirmada (aguarda a lib, sem fsync)', kDurableOps),
  fsyncWrite('Escrita durável com fsync (só o all_box oferece)', kDurableOps),
  burstThenFlush('Burst de $kDurableOps writes + 1 flush', kDurableOps);

  const Scenario(this.label, this.ops);

  final String label;
  final int ops;
}

class ScenarioResult {
  ScenarioResult(this.scenario, this.elapsed);

  final Scenario scenario;
  final Duration elapsed;

  double get perOpMicros => elapsed.inMicroseconds / scenario.ops;

  double get opsPerSec =>
      scenario.ops / (elapsed.inMicroseconds / Duration.microsecondsPerSecond);
}

class LibResult {
  LibResult(this.libName, this.results);

  final String libName;
  final List<ScenarioResult> results;

  ScenarioResult? operator [](Scenario s) {
    for (final r in results) {
      if (r.scenario == s) return r;
    }
    return null;
  }
}

/// Uniform surface over each storage lib so every scenario runs the exact
/// same loop. Each adapter maps the scenario to that lib's closest
/// equivalent (documented per adapter).
///
/// **PT-BR:** Superfície uniforme sobre cada lib, para todo cenário rodar
/// exatamente o mesmo loop. Cada adapter mapeia o cenário para o
/// equivalente mais próximo daquela lib (documentado em cada um).
abstract class StorageAdapter {
  String get name;

  Future<void> setup(String basePath);

  /// Fire-and-forget write: memory updated now, disk catches up later.
  void writeFast(String key, int value);

  /// Write that only completes when the lib considers it persisted — each
  /// lib's own definition of "persisted", which for none of the popular
  /// ones includes an fsync. This is the apples-to-apples row.
  Future<void> writeDurable(String key, int value);

  /// Write that only completes after a real fsync, i.e. the data survives
  /// power loss. `null` when the lib has no API offering this guarantee
  /// (which is every lib in this comparison except all_box).
  Future<void> Function(String key, int value)? get writeFsync => null;

  int? read(String key);

  /// Settle whatever [writeFast] left pending.
  Future<void> settle();

  /// Removes every key, so one scenario's leftovers (e.g. 10.000 keys from
  /// the memory pass) don't inflate the cost of the next one (e.g. durable
  /// writes, where some libs rewrite the whole container per flush).
  Future<void> clear();
}

class AllBoxAdapter extends StorageAdapter {
  late AllBox _box;

  @override
  String get name => 'all_box';

  @override
  Future<void> setup(String basePath) async {
    await AllBox.init('bench_all_box', path: '$basePath/all_box');
    _box = AllBox('bench_all_box');
  }

  @override
  void writeFast(String key, int value) => _box.write(key, value);

  @override
  Future<void> writeDurable(String key, int value) =>
      _box.writeAndSave(key, value); // waits for the OS write, no fsync —
  // the same guarantee class as Hive's put / SharedPreferences' set.

  @override
  Future<void> Function(String key, int value)? get writeFsync =>
      (key, value) => _box.writeAndFlush(key, value); // real fsync per call

  @override
  int? read(String key) => _box.read<int>(key);

  @override
  Future<void> settle() => _box.flushNow();

  @override
  Future<void> clear() async {
    _box.erase();
    await _box.flushNow();
  }
}

// GetStorage was removed from the measured comparison: its `write()`
// Future resolves after scheduling a microtask, without waiting even for
// the buffered OS write (see `Microtask.exec` in get_storage's
// storage_impl.dart — it returns void and drops the callback when one is
// already scheduled). There is no API in GetStorage that waits for data to
// reach disk, so there is nothing comparable to measure in the
// confirmed/fsync/burst rows. The qualitative comparison in
// `documentation/*/comparison.md` still covers it.
//
// **PT-BR:** O GetStorage foi removido do comparativo medido: o Future do
// `write()` dele resolve após agendar um microtask, sem esperar nem o
// write bufferizado do OS (veja `Microtask.exec` no storage_impl.dart do
// get_storage — retorna void e descarta o callback quando já existe um
// agendado). Não há API no GetStorage que espere o dado chegar ao disco,
// então não existe nada comparável a medir nas linhas de
// confirmada/fsync/burst. A comparação qualitativa em
// `documentation/*/comparison.md` continua cobrindo ele.

class HiveAdapter extends StorageAdapter {
  late Box<dynamic> _box;
  static bool _initialized = false;

  @override
  String get name => 'Hive';

  @override
  Future<void> setup(String basePath) async {
    if (!_initialized) {
      Hive.init('$basePath/hive');
      _initialized = true;
    }
    _box = await Hive.openBox<dynamic>('bench_hive');
  }

  @override
  void writeFast(String key, int value) {
    unawaited(_box.put(key, value));
  }

  @override
  Future<void> writeDurable(String key, int value) =>
      _box.put(key, value); // append to log, no fsync — cheaper guarantee

  @override
  int? read(String key) => _box.get(key) as int?;

  @override
  Future<void> settle() => _box.flush();

  @override
  Future<void> clear() => _box.clear().then((_) {});
}

class SharedPreferencesAdapter extends StorageAdapter {
  late SharedPreferences _prefs;
  final List<Future<void>> _pending = <Future<void>>[];

  @override
  String get name => 'SharedPreferences';

  @override
  Future<void> setup(String basePath) async {
    // SharedPreferences resolves its own platform-specific location; the
    // basePath is intentionally unused here.
    _prefs = await SharedPreferences.getInstance();
  }

  @override
  void writeFast(String key, int value) {
    // Memory cache updates synchronously; the platform write is the Future.
    _pending.add(_prefs.setInt(key, value));
  }

  @override
  Future<void> writeDurable(String key, int value) => _prefs.setInt(key, value);

  @override
  int? read(String key) => _prefs.getInt(key);

  @override
  Future<void> settle() async {
    await Future.wait(_pending);
    _pending.clear();
  }

  @override
  Future<void> clear() async {
    await _prefs.clear();
  }
}

/// Runs [rounds] rounds of [round] and returns the MEDIAN elapsed time.
/// The median (not the mean, not a single pass) is what makes rankings
/// stable between runs: one GC pause or background-I/O hiccup lands in a
/// single round and gets discarded.
///
/// **PT-BR:** Roda [rounds] rodadas de [round] e retorna a MEDIANA. A
/// mediana (não a média, não uma passada única) é o que estabiliza o
/// ranking entre execuções: uma pausa de GC ou I/O de fundo cai em uma
/// rodada só e é descartada.
Future<Duration> _medianOf(
  int rounds,
  Future<Duration> Function() round,
) async {
  final samples = <Duration>[];
  for (var i = 0; i < rounds; i++) {
    samples.add(await round());
    // Yield so the UI can repaint between rounds.
    await Future<void>.delayed(Duration.zero);
  }
  samples.sort();
  return samples[samples.length ~/ 2];
}

/// Runs all four scenarios against [adapter]. Scenarios run sequentially,
/// each one over multiple rounds (median reported), with the container
/// cleared between scenarios so leftovers from one never inflate the next.
Future<LibResult> runBenchmark(
  StorageAdapter adapter,
  String basePath, {
  void Function(String message)? onProgress,
}) async {
  onProgress?.call('${adapter.name}: preparando…');
  await adapter.setup(basePath);

  final results = <ScenarioResult>[];

  // Warm-up: JIT + first-touch costs must not land inside the measurement.
  for (var i = 0; i < 100; i++) {
    adapter.writeFast('warmup_$i', i);
  }
  await adapter.settle();
  await adapter.clear();

  // 1) Optimistic writes to distinct keys (settle happens per round, but
  //    outside the measured window).
  onProgress?.call('${adapter.name}: escrita otimista…');
  final optimistic = await _medianOf(kMemoryRounds, () async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < kMemoryOps; i++) {
      adapter.writeFast('key_$i', i);
    }
    sw.stop();
    await adapter.settle();
    return sw.elapsed;
  });
  results.add(ScenarioResult(Scenario.optimisticWrite, optimistic));

  // 2) Synchronous reads of the keys written above.
  onProgress?.call('${adapter.name}: leitura síncrona…');
  var checksum = 0;
  final read = await _medianOf(kMemoryRounds, () async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < kMemoryOps; i++) {
      checksum += adapter.read('key_$i') ?? 0;
    }
    sw.stop();
    return sw.elapsed;
  });
  // Consume the checksum so the loop cannot be optimized away.
  assert(checksum >= 0);
  results.add(ScenarioResult(Scenario.syncRead, read));

  // The 10.000 keys above must not inflate the durable scenarios below
  // (some libs rewrite the whole container per flush).
  await adapter.clear();

  // 3) Confirmed writes, awaited one by one, same key — each lib's own
  //    "persisted" contract (none of them fsyncs here): apples to apples.
  onProgress?.call('${adapter.name}: escrita confirmada…');
  final confirmed = await _medianOf(kDurableRounds, () async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < kDurableOps; i++) {
      await adapter.writeDurable('counter', i);
    }
    sw.stop();
    return sw.elapsed;
  });
  results.add(ScenarioResult(Scenario.confirmedWrite, confirmed));

  // 3b) Fsync writes — only offered by all_box; the card for this scenario
  //     shows a single bar, which is exactly the point.
  final writeFsync = adapter.writeFsync;
  if (writeFsync != null) {
    onProgress?.call('${adapter.name}: escrita durável (fsync)…');
    final fsynced = await _medianOf(kDurableRounds, () async {
      final sw = Stopwatch()..start();
      for (var i = 0; i < kDurableOps; i++) {
        await writeFsync('counter', i);
      }
      sw.stop();
      return sw.elapsed;
    });
    results.add(ScenarioResult(Scenario.fsyncWrite, fsynced));
  }

  // 4) Burst of fast writes + one settle (all_box's debounce sweet spot;
  //    for the others this measures their own pending-write draining).
  onProgress?.call('${adapter.name}: burst + flush…');
  final burst = await _medianOf(kDurableRounds, () async {
    final sw = Stopwatch()..start();
    for (var i = 0; i < kDurableOps; i++) {
      adapter.writeFast('burst', i);
    }
    await adapter.settle();
    sw.stop();
    return sw.elapsed;
  });
  results.add(ScenarioResult(Scenario.burstThenFlush, burst));

  return LibResult(adapter.name, results);
}

/// Formats [results] as a Markdown table, ready to paste into the README.
String resultsAsMarkdown(List<LibResult> results, String environment) {
  final buffer = StringBuffer()
    ..writeln('### Benchmark on-device')
    ..writeln()
    ..writeln(environment)
    ..writeln()
    ..write('| Cenário |');
  for (final lib in results) {
    buffer.write(' ${lib.libName} |');
  }
  buffer
    ..writeln()
    ..write('|---|');
  for (final _ in results) {
    buffer.write('---|');
  }
  buffer.writeln();
  for (final scenario in Scenario.values) {
    buffer.write('| ${scenario.label} |');
    for (final lib in results) {
      final r = lib[scenario];
      buffer.write(
        r == null
            ? ' — |'
            : ' ${r.elapsed.inMilliseconds}ms '
                '(${r.perOpMicros.toStringAsFixed(1)}µs/op) |',
      );
    }
    buffer.writeln();
  }
  buffer
    ..writeln()
    ..writeln(
      '_Escrita confirmada: cada lib com o próprio contrato de "persistido" '
      '(nenhuma faz fsync aí). A linha de fsync só existe para o all_box '
      'porque nenhuma das outras oferece essa garantia._',
    );
  return buffer.toString();
}
