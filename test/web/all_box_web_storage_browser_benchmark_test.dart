@TestOn('browser')
@Tags(['benchmark'])
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

extension type _JSStorage._(JSObject _) implements JSObject {
  external JSString? getItem(JSString key);
  external void removeItem(JSString key);
}

@JS('window.localStorage')
external _JSStorage get _localStorage;

String? _rawGet(String key) => _localStorage.getItem(key.toJS)?.toDart;
void _rawRemove(String key) => _localStorage.removeItem(key.toJS);

void main() {
  test('prints a real-browser localStorage benchmark report', () async {
    final report = <Map<String, Object?>>[];

    for (final keys in <int>[100, 1000, 5000]) {
      report.add(await _runSnapshotScenario(
        name: 'browser_keys_$keys',
        snapshot: <String, dynamic>{
          for (var i = 0; i < keys; i++) 'key_$i': 'value_$i',
        },
      ));
    }

    for (final sizeKb in <int>[100, 500, 1024]) {
      report.add(await _runSnapshotScenario(
        name: 'browser_single_value_${sizeKb}kb',
        snapshot: <String, dynamic>{'blob': 'x' * (sizeKb * 1024)},
      ));
    }

    // ignore: avoid_print
    print(const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'environment': 'Browser test runner with real window.localStorage',
      'note': 'Use as a local comparison report. Do not treat absolute '
          'times as portable pass/fail thresholds.',
      'results': report,
    }));
  });
}

Future<Map<String, Object?>> _runSnapshotScenario({
  required String name,
  required Map<String, dynamic> snapshot,
}) async {
  final container = 'all_box_$name';
  final storageKey = 'all_box::$container';

  AllBox.resetInstanceForTesting(container);
  _rawRemove(storageKey);
  addTearDown(() {
    AllBox.resetInstanceForTesting(container);
    _rawRemove(storageKey);
  });

  final initWatch = Stopwatch()..start();
  final box = await AllBox.init(container);
  initWatch.stop();

  final writeWatch = Stopwatch()..start();
  for (final entry in snapshot.entries) {
    box.write(entry.key, entry.value);
  }
  await box.flushNow();
  writeWatch.stop();

  final storedBytes = _rawGet(storageKey)?.length ?? 0;

  AllBox.resetInstanceForTesting(container);
  final reloadWatch = Stopwatch()..start();
  final reloaded = await AllBox.init(container);
  reloadWatch.stop();

  expect(reloaded.getKeys().length, snapshot.length);

  return <String, Object?>{
    'scenario': name,
    'keys': snapshot.length,
    'storedBytes': storedBytes,
    'initMs': initWatch.elapsedMicroseconds / 1000,
    'writeAndFlushMs': writeWatch.elapsedMicroseconds / 1000,
    'reloadMs': reloadWatch.elapsedMicroseconds / 1000,
  };
}
