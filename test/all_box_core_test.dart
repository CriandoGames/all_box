// Tests for the AllBox core (package:all_box/all_box.dart): pure Dart, no
// reactivity involved (all_box has no listener/reactive API anymore).
//
// **PT-BR:** Testes do core do AllBox (package:all_box/all_box.dart): Dart
// puro, sem nenhuma reatividade envolvida (o all_box não tem mais nenhuma
// API de listener/reatividade).

// The 'initWithMemoryBackendForTesting' group below intentionally exercises
// the deprecated alias to confirm it still works as a thin wrapper around
// AllBox.memory().
// ignore_for_file: deprecated_member_use_from_same_package

import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

/// Each test gets its own temp directory and its own container name, so
/// containers never collide with the static singleton cache across tests
/// running in the same isolate.
Future<Directory> _tempDir(String label) async {
  final dir = await Directory.systemTemp.createTemp('all_box_${label}_');
  addTearDown(() async {
    AllBox.resetInstanceForTesting(label);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

void main() {
  group('crash-safety on read', () {
    test('random binary bytes in <container>.db do not crash init()', () async {
      const container = 'corrupted_binary';
      final dir = await _tempDir(container);

      // Simulate a process that died mid-write, or disk corruption: the
      // main file exists but contains garbage bytes that are not valid
      // UTF-8, so `utf8.decode` must fail before `jsonDecode` even runs.
      final dbFile = File('${dir.path}/$container.db');
      final random = Random(42);
      final garbage = Uint8List.fromList(
        List<int>.generate(256, (_) => random.nextInt(256)),
      );
      await dbFile.writeAsBytes(garbage);

      // Must not throw.
      await expectLater(
        AllBox.init(container, path: dir.path),
        completes,
      );

      final box = AllBox(container);
      expect(box.isInitialized, isTrue);
      expect(box.getKeys(), isEmpty);

      // The container must still be fully usable afterwards.
      box.write('hello', 'world');
      expect(box.read<String>('hello'), 'world');
    });

    test('valid UTF-8 but invalid JSON in <container>.db falls back safely',
        () async {
      const container = 'invalid_json';
      final dir = await _tempDir(container);

      final dbFile = File('${dir.path}/$container.db');
      await dbFile.writeAsString('{ this is not json ][');

      await expectLater(AllBox.init(container, path: dir.path), completes);

      final box = AllBox(container);
      expect(box.getKeys(), isEmpty);
    });

    test('falls back to the .bak file when the main file is corrupted',
        () async {
      const container = 'fallback_to_backup';
      final dir = await _tempDir(container);

      await File('${dir.path}/$container.bak')
          .writeAsString('{"greeting":"from backup"}');
      await File('${dir.path}/$container.db')
          .writeAsBytes(<int>[0xFF, 0x00, 0xDE, 0xAD]);

      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      expect(box.read<String>('greeting'), 'from backup');
    });

    test('logs a debug diagnostic when db and bak are both corrupted',
        () async {
      const container = 'corrupted_with_diagnostic';
      final dir = await _tempDir(container);
      final logs = <String>[];

      await File('${dir.path}/$container.db')
          .writeAsBytes(<int>[0xFF, 0x00, 0xDE, 0xAD]);
      await File('${dir.path}/$container.bak').writeAsString('{ broken json');

      await runZoned(
        () => AllBox.init(
          container,
          path: dir.path,
          initialData: const {'seed': 'must-not-mask-corruption'},
        ),
        zoneSpecification: ZoneSpecification(
          print: (_, __, ___, message) => logs.add(message),
        ),
      );

      final box = AllBox(container);
      expect(box.getKeys(), isEmpty);
      expect(
        logs.join('\n'),
        allOf(
          contains('AllBox("$container")'),
          contains('corrupted or unreadable'),
          contains('$container.db'),
          contains('$container.bak'),
        ),
      );
    });
  });

  group('initialData seed', () {
    test('seeds a brand-new container and persists it immediately', () async {
      const container = 'seed_first_run';
      final dir = await _tempDir(container);

      await AllBox.init(
        container,
        path: dir.path,
        initialData: const {'darkMode': true, 'onboarded': false},
      );
      final box = AllBox(container);

      expect(box.read<bool>('darkMode'), isTrue);
      expect(box.read<bool>('onboarded'), isFalse);

      // The seed must already be on disk, not just in memory — a crash
      // right after this init() should not lose it.
      final dbFile = File('${dir.path}/$container.db');
      expect(dbFile.existsSync(), isTrue);
      expect(jsonDecode(await dbFile.readAsString()), {
        'darkMode': true,
        'onboarded': false,
      });
    });

    test('is ignored when the container was already persisted before',
        () async {
      const container = 'seed_ignored_when_persisted';
      final dir = await _tempDir(container);

      await File('${dir.path}/$container.db')
          .writeAsString('{"darkMode":false}');

      await AllBox.init(
        container,
        path: dir.path,
        initialData: const {'darkMode': true, 'onboarded': true},
      );
      final box = AllBox(container);

      // Whatever was already on disk wins; the seed never overwrites it.
      expect(box.read<bool>('darkMode'), isFalse);
      expect(box.hasData('onboarded'), isFalse);
    });

    test('is ignored for a container previously left empty by erase()',
        () async {
      const container = 'seed_ignored_after_erase';
      final dir = await _tempDir(container);

      // An empty `{}` written by a prior erase() still counts as
      // "persisted before" — it must not be reseeded on the next launch.
      await File('${dir.path}/$container.db').writeAsString('{}');

      await AllBox.init(
        container,
        path: dir.path,
        initialData: const {'darkMode': true},
      );
      final box = AllBox(container);

      expect(box.hasData('darkMode'), isFalse);
      expect(box.getKeys(), isEmpty);
    });
  });

  group('debounced writes', () {
    test('several write() calls in quick succession produce a single flush',
        () async {
      const container = 'debounce_test';
      final dir = await _tempDir(container);

      await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(milliseconds: 150),
      );
      final box = AllBox(container);

      final tmpPath = '${dir.path}/$container.tmp';

      for (var i = 0; i < 10; i++) {
        box.write('counter', i);
      }

      // Optimistic write: memory is already updated synchronously, before
      // any disk activity has had a chance to happen.
      expect(box.read<int>('counter'), 9);
      expect(File(tmpPath).existsSync(), isFalse);
      expect(box.flushCountForTesting, 0);

      await Future<void>.delayed(const Duration(milliseconds: 500));

      // Counting actual `_writeToDisk` calls instead of watching the
      // filesystem for notifications: `Directory.watch()` is notoriously
      // unreliable on Windows (events can be dropped, coalesced or
      // delayed — see dart-lang/sdk#37233), which made this assertion flaky
      // there despite the debounce logic itself working correctly.
      expect(
        box.flushCountForTesting,
        1,
        reason: 'expected exactly one flush to disk despite 10 write() calls',
      );

      final persisted = await File('${dir.path}/$container.db').readAsString();
      expect(persisted, contains('"counter":9'));
    });

    test('writeAndFlush bypasses the debounce window', () async {
      const container = 'write_and_flush';
      final dir = await _tempDir(container);
      await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(seconds: 5),
      );
      final box = AllBox(container);

      await box.writeAndFlush('key', 'value');

      final persisted = await File('${dir.path}/$container.db').readAsString();
      expect(persisted, contains('"key":"value"'));
    });
  });

  group('container isolation', () {
    test('two containers never leak data into each other', () async {
      final dirA = await _tempDir('container_a');
      final dirB = await _tempDir('container_b');

      await AllBox.init('container_a', path: dirA.path);
      await AllBox.init('container_b', path: dirB.path);

      final boxA = AllBox('container_a');
      final boxB = AllBox('container_b');

      boxA.write('shared_key', 'value from A');
      boxB.write('shared_key', 'value from B');

      expect(boxA.read<String>('shared_key'), 'value from A');
      expect(boxB.read<String>('shared_key'), 'value from B');

      boxA.write('only_in_a', true);
      expect(boxB.hasData('only_in_a'), isFalse);

      await boxA.flushNow();
      await boxB.flushNow();

      expect(File('${dirA.path}/container_a.db').existsSync(), isTrue);
      expect(File('${dirB.path}/container_b.db').existsSync(), isTrue);
      expect(File('${dirA.path}/container_b.db').existsSync(), isFalse);
    });
  });

  group('erase()', () {
    test('clears every key in the container', () async {
      const container = 'erase_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      box.write('a', 1);
      box.write('b', 2);

      box.erase();

      expect(box.getKeys(), isEmpty);
    });
  });

  group('initWithMemoryBackendForTesting', () {
    test('seeds initial values and reads/writes work synchronously', () async {
      const container = 'memory_backend_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await AllBox.memory(
        container,
        initialData: {'seeded': 'value'},
      );
      final box = AllBox(container);

      expect(box.read<String>('seeded'), 'value');

      box.write('counter', 1);
      expect(box.read<int>('counter'), 1);
    });

    test('does not schedule any real Timer on write', () async {
      const container = 'memory_backend_no_timer_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await AllBox.initWithMemoryBackendForTesting(container);
      final box = AllBox(container);

      box.write('a', 1);
      box.write('b', 2);

      // Every write "flushes" synchronously against the in-memory backend,
      // so there's no debounce window to wait out here — if this were a
      // disk-backed container, this assertion would need a real delay.
      expect(box.flushCountForTesting, 2);
    });

    test('resetInstanceForTesting clears the cached singleton', () async {
      const container = 'memory_backend_reset_test';

      await AllBox.initWithMemoryBackendForTesting(
        container,
        initialValues: {'k': 'v'},
      );
      AllBox.resetInstanceForTesting(container);

      await AllBox.initWithMemoryBackendForTesting(container);
      final box = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      // A fresh init() after reset must not see the previous instance's
      // in-memory data.
      expect(box.hasData('k'), isFalse);
    });
  });

  group('write() serialization guard', () {
    test(
        'writes a non-JSON-encodable value to memory anyway, without '
        'throwing (only a debug warning is logged)', () async {
      const container = 'serialization_guard_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await AllBox.initWithMemoryBackendForTesting(container);
      final box = AllBox(container);

      // DateTime has no built-in toJson(); jsonEncode() rejects it. This
      // never throws — it's only ever reported via a debug-mode debug log.
      // It will still silently fail to reach disk once a real, disk-backed
      // flush actually tries to jsonEncode() it.
      expect(() => box.write('when', DateTime.now()), returnsNormally);
      expect(box.hasData('when'), isTrue);
    });

    test(
        'writeAndFlush() does not throw for a non-JSON-encodable value '
        'against the in-memory test backend (which never encodes to JSON)',
        () async {
      const container = 'serialization_guard_flush_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await AllBox.initWithMemoryBackendForTesting(container);
      final box = AllBox(container);

      await expectLater(
        box.writeAndFlush('when', DateTime.now()),
        completes,
      );
      expect(box.hasData('when'), isTrue);
    });
  });
}
