import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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
      final createEvents = <FileSystemEvent>[];
      final sub = dir.watch().listen((event) {
        if (event.path == tmpPath) createEvents.add(event);
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));

      for (var i = 0; i < 10; i++) {
        box.write('counter', i);
      }

      // Optimistic write: memory is already updated synchronously, before
      // any disk activity has had a chance to happen.
      expect(box.read<int>('counter'), 9);
      expect(File(tmpPath).existsSync(), isFalse);

      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sub.cancel();

      final creates = createEvents.whereType<FileSystemCreateEvent>().length;
      expect(
        creates,
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
    test('notifies every listener whose key existed before clearing', () async {
      const container = 'erase_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      box.write('a', 1);
      box.write('b', 2);

      var aNotified = 0;
      var bNotified = 0;
      var globalNotified = 0;

      box.listenKey('a', () => aNotified++);
      box.listenKey('b', () => bNotified++);
      box.listenAll(() => globalNotified++);

      box.erase();

      expect(aNotified, 1);
      expect(bNotified, 1);
      expect(globalNotified, 1);
      expect(box.getKeys(), isEmpty);
    });
  });

  group('listenKey / listenAll lifecycle', () {
    test('listenKey stops firing after removeListenKey', () async {
      const container = 'listen_key_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      var callCount = 0;
      void callback() => callCount++;

      box.listenKey('k', callback);
      box.write('k', 1);
      expect(callCount, 1);

      box.removeListenKey('k', callback);
      box.write('k', 2);
      expect(callCount, 1, reason: 'listener must not fire after removal');
    });

    test('listenAll dispose function removes the listener (no leak)', () async {
      const container = 'listen_all_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      var callCount = 0;
      final dispose = box.listenAll(() => callCount++);

      box.write('x', 1);
      expect(callCount, 1);

      dispose();
      box.write('x', 2);
      expect(callCount, 1,
          reason: 'global listener must not fire after dispose');
    });

    test('AllBoxListenable removes its key listener on dispose', () async {
      const container = 'listenable_dispose_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      final listenable = AllBoxListenable<int>('n', box: box);
      var notifyCount = 0;
      listenable.addListener(() => notifyCount++);

      box.write('n', 1);
      expect(notifyCount, 1);
      expect(listenable.value, 1);

      listenable.dispose();
      box.write('n', 2);
      // The ChangeNotifier itself was disposed and unsubscribed, so no new
      // notifications should have been recorded.
      expect(notifyCount, 1);
    });
  });

  group('AllBoxBuilder widget', () {
    testWidgets('rebuilds when the watched key changes', (tester) async {
      const container = 'builder_widget_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await tester.pumpWidget(
        MaterialApp(
          home: AllBoxBuilder<int>(
            keyName: 'count',
            box: box,
            builder: (context, value) => Text('count: ${value ?? 0}'),
          ),
        ),
      );

      expect(find.text('count: 0'), findsOneWidget);

      box.write('count', 5);
      await tester.pump();

      expect(find.text('count: 5'), findsOneWidget);
    });
  });

  group('.val() extension', () {
    test('reads defaults and persists writes without any DI coupling',
        () async {
      const container = 'val_extension_test';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      final darkMode = 'darkMode'.val(false, box: box);
      expect(darkMode.value, isFalse);

      darkMode.value = true;
      expect(darkMode.value, isTrue);
      expect(box.read<bool>('darkMode'), isTrue);
    });
  });
}
