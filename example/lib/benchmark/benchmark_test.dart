// Wrapper to run the benchmark through `flutter test`, since `all_box`
// depends on `flutter/foundation` and therefore cannot run on the plain
// Dart VM (`dart run` fails with a `dart:ui` resolution error).
//
// Run with:
//   flutter test benchmark/benchmark_test.dart
//
// **PT-BR:** Wrapper para rodar o benchmark via `flutter test`, já que o
// `all_box` depende de `flutter/foundation` e por isso não roda na VM pura
// do Dart (`dart run` falha com erro de resolução de `dart:ui`).

import 'package:flutter_test/flutter_test.dart';

import '../../../benchmark/benchmark.dart' as bench;

void main() {
  test(
    'run benchmark suite',
    bench.main,
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
