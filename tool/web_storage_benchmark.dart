import 'dart:convert';

import 'package:all_box/src/core/storage/all_box_storage.dart';
import 'package:all_box/src/core/storage/all_box_web_storage.dart';

Future<void> main() async {
  final scenarios = <_Scenario>[
    for (final keys in <int>[100, 1000, 5000]) _KeyCountScenario(keys),
    for (final sizeKb in <int>[100, 500, 1024]) _LargeValueScenario(sizeKb),
    _BurstScenario(writes: 1000),
    _MultiContainerScenario(containers: 20, keysPerContainer: 100),
  ];

  final report = <Map<String, Object?>>[];
  for (final scenario in scenarios) {
    report.add(await scenario.run());
  }

  const encoder = JsonEncoder.withIndent('  ');
  // ignore: avoid_print
  print(encoder.convert(<String, Object?>{
    'environment': 'Dart VM with fake synchronous browser storage',
    'note': 'Use as a comparative local benchmark. Do not treat absolute '
        'times as portable pass/fail thresholds.',
    'results': report,
  }));
}

abstract class _Scenario {
  String get name;
  Future<Map<String, Object?>> run();
}

class _KeyCountScenario implements _Scenario {
  _KeyCountScenario(this.keys);

  final int keys;

  @override
  String get name => 'keys_$keys';

  @override
  Future<Map<String, Object?>> run() async {
    final snapshot = <String, dynamic>{
      for (var i = 0; i < keys; i++) 'key_$i': 'value_$i',
    };
    return _measureSaveLoad(name, snapshot);
  }
}

class _LargeValueScenario implements _Scenario {
  _LargeValueScenario(this.sizeKb);

  final int sizeKb;

  @override
  String get name => 'single_value_${sizeKb}kb';

  @override
  Future<Map<String, Object?>> run() async {
    return _measureSaveLoad(name, <String, dynamic>{
      'blob': 'x' * (sizeKb * 1024),
    });
  }
}

class _BurstScenario implements _Scenario {
  _BurstScenario({required this.writes});

  final int writes;

  @override
  String get name => 'burst_$writes';

  @override
  Future<Map<String, Object?>> run() async {
    final browser = _FakeBrowserStorage();
    final storage = AllBoxWebStorage(container: name, browserStorage: browser);
    final snapshot = <String, dynamic>{};
    final stopwatch = Stopwatch()..start();
    for (var i = 0; i < writes; i++) {
      snapshot['key_$i'] = i;
      await storage.save(snapshot, mode: AllBoxPersistMode.save);
    }
    stopwatch.stop();

    return <String, Object?>{
      'scenario': name,
      'writes': writes,
      'storedBytes': browser.lastValueLength,
      'setItemCalls': browser.setItemCalls,
      'totalMs': stopwatch.elapsedMicroseconds / 1000,
    };
  }
}

class _MultiContainerScenario implements _Scenario {
  _MultiContainerScenario({
    required this.containers,
    required this.keysPerContainer,
  });

  final int containers;
  final int keysPerContainer;

  @override
  String get name => 'multi_container_${containers}_x_$keysPerContainer';

  @override
  Future<Map<String, Object?>> run() async {
    final browser = _FakeBrowserStorage();
    final stopwatch = Stopwatch()..start();
    for (var c = 0; c < containers; c++) {
      final storage = AllBoxWebStorage(
        container: 'container_$c',
        browserStorage: browser,
      );
      await storage.save(<String, dynamic>{
        for (var i = 0; i < keysPerContainer; i++) 'key_$i': i,
      }, mode: AllBoxPersistMode.save);
    }
    stopwatch.stop();

    return <String, Object?>{
      'scenario': name,
      'containers': containers,
      'keysPerContainer': keysPerContainer,
      'setItemCalls': browser.setItemCalls,
      'totalStoredBytes': browser.totalValueLength,
      'totalMs': stopwatch.elapsedMicroseconds / 1000,
    };
  }
}

Future<Map<String, Object?>> _measureSaveLoad(
  String name,
  Map<String, dynamic> snapshot,
) async {
  final browser = _FakeBrowserStorage();
  final storage = AllBoxWebStorage(container: name, browserStorage: browser);

  final encodeWatch = Stopwatch()..start();
  final encoded = jsonEncode(snapshot);
  encodeWatch.stop();

  final saveWatch = Stopwatch()..start();
  await storage.save(snapshot, mode: AllBoxPersistMode.save);
  saveWatch.stop();

  final loadWatch = Stopwatch()..start();
  final loaded = await storage.load();
  loadWatch.stop();

  return <String, Object?>{
    'scenario': name,
    'keys': snapshot.length,
    'encodedBytes': encoded.length,
    'jsonEncodeMs': encodeWatch.elapsedMicroseconds / 1000,
    'saveMs': saveWatch.elapsedMicroseconds / 1000,
    'loadMs': loadWatch.elapsedMicroseconds / 1000,
    'setItemCalls': browser.setItemCalls,
    'roundTripKeys': loaded.length,
  };
}

class _FakeBrowserStorage implements AllBoxBrowserStorage {
  final Map<String, String> _map = <String, String>{};
  int setItemCalls = 0;

  int get lastValueLength => _map.isEmpty ? 0 : _map.values.last.length;
  int get totalValueLength =>
      _map.values.fold<int>(0, (total, value) => total + value.length);

  @override
  String? getItem(String key) => _map[key];

  @override
  void removeItem(String key) {
    _map.remove(key);
  }

  @override
  void setItem(String key, String value) {
    setItemCalls++;
    _map[key] = value;
  }
}
