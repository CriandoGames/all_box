// ignore_for_file: avoid_print
//
// Own benchmark for `all_box`.
//
// This script measures `all_box` itself, on whatever machine/disk you run
// it on — no numbers borrowed from anywhere else.
//
// Methodology
// -----------
// 1. In-memory write throughput: `N` sequential `write()` calls to distinct
//    keys, timed with a `Stopwatch`. This measures only the synchronous,
//    optimistic part of a write (memory update + listener notification) —
//    disk flushing is debounced and happens after this loop returns, so it
//    is intentionally NOT included here.
// 2. In-memory read throughput: `N` sequential `read<int>()` calls against
//    the keys written above, same methodology.
// 3. End-to-end flush latency: `N` sequential `writeAndFlush()` calls to the
//    SAME key, timed individually. Because flushes are serialized (see
//    README), each call here waits for its own real `write-ahead tmp write
//    + backup rename + atomic rename` round trip to finish — this is the
//    realistic "durable write" cost, disk included.
// 4. Debounce effectiveness: `N` rapid `write()` calls followed by a single
//    `flushNow()`, timed as one unit, to illustrate the savings versus (3).
//
// Run with:
//   flutter pub get
//   flutter test benchmark/benchmark_test.dart
//
// (`dart run` does not work here: the package imports
// `flutter/foundation`, which the plain Dart VM cannot resolve.)
//
// Results are printed as ops/sec and average µs/op. They are only
// meaningful relative to each other, on your machine, on your disk — do not
// treat them as portable numbers.

import 'dart:io';

import 'package:all_box/all_box.dart';

const int kOpCount = 2000;
const int kFlushOpCount = 200; // fewer: real disk I/O per op is much slower

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp('all_box_benchmark_');
  print('Working directory: ${tempDir.path}');
  print('Dart: ${Platform.version}');
  print('OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
  print('');

  try {
    await _benchmarkMemoryWrites(tempDir.path);
    await _benchmarkMemoryReads(tempDir.path);
    await _benchmarkDurableWrites(tempDir.path);
    await _benchmarkDebouncedBurst(tempDir.path);
  } finally {
    await tempDir.delete(recursive: true);
  }
}

void _report(String label, int ops, Duration elapsed) {
  final micros = elapsed.inMicroseconds;
  final perOpMicros = micros / ops;
  final opsPerSec = ops / (micros / Duration.microsecondsPerSecond);
  print(
    '$label: $ops ops in $microsµs '
    '(${perOpMicros.toStringAsFixed(2)}µs/op, '
    '${opsPerSec.toStringAsFixed(0)} ops/sec)',
  );
}

Future<void> _benchmarkMemoryWrites(String basePath) async {
  const container = 'bench_memory_writes';
  await AllBox.init(container, path: '$basePath/$container');
  final box = AllBox(container);

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < kOpCount; i++) {
    box.write('key_$i', i);
  }
  stopwatch.stop();

  _report('In-memory write() (optimistic, no disk wait)', kOpCount,
      stopwatch.elapsed);
}

Future<void> _benchmarkMemoryReads(String basePath) async {
  const container = 'bench_memory_reads';
  await AllBox.init(container, path: '$basePath/$container');
  final box = AllBox(container);

  for (var i = 0; i < kOpCount; i++) {
    box.write('key_$i', i);
  }
  await box.flushNow();

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < kOpCount; i++) {
    box.read<int>('key_$i');
  }
  stopwatch.stop();

  _report('Synchronous read<int>()', kOpCount, stopwatch.elapsed);
}

Future<void> _benchmarkDurableWrites(String basePath) async {
  const container = 'bench_durable_writes';
  await AllBox.init(container, path: '$basePath/$container');
  final box = AllBox(container);

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < kFlushOpCount; i++) {
    await box.writeAndFlush('counter', i);
  }
  stopwatch.stop();

  _report(
    'writeAndFlush() (tmp write + backup rename + atomic rename, per call)',
    kFlushOpCount,
    stopwatch.elapsed,
  );
}

Future<void> _benchmarkDebouncedBurst(String basePath) async {
  const container = 'bench_debounced_burst';
  await AllBox.init(container, path: '$basePath/$container');
  final box = AllBox(container);

  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < kFlushOpCount; i++) {
    box.write('counter', i); // debounced: no disk I/O yet
  }
  await box.flushNow(); // exactly one real flush for the whole burst
  stopwatch.stop();

  _report(
    '$kFlushOpCount debounced write() + a single flushNow() (whole burst)',
    kFlushOpCount,
    stopwatch.elapsed,
  );
}
