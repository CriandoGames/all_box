// Tests for AllBox's optional Flutter layer (package:all_box/all_box_flutter.dart):
// AllBoxListenable and AllBoxBuilder. Core-only behavior (crash-safety,
// debounce, persistence, ...) lives in test/all_box_core_test.dart instead.
//
// **PT-BR:** Testes da camada opcional de Flutter do AllBox
// (package:all_box/all_box_flutter.dart): AllBoxListenable e AllBoxBuilder.
// O comportamento exclusivo do core (crash-safety, debounce, persistência,
// ...) fica em test/all_box_core_test.dart.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:all_box/all_box_flutter.dart';

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
  group('listenKey / listenAll lifecycle', () {
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

  testWidgets('smoke', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Text('oi')));
    expect(find.text('oi'), findsOneWidget);
  });

  group('AllBoxBuilder widget', () {
    testWidgets('rebuilds when the watched key changes', (tester) async {
      const container = 'builder_widget_test';
      // In-memory backend on purpose, not a real temp dir + AllBox.init():
      // `write()` on a disk-backed container schedules a real debounce
      // `Timer`, and `testWidgets` runs inside a FakeAsync zone that expects
      // every Timer to be resolved before the test ends — one left pending
      // there hangs the test runner instead of failing it. The in-memory
      // backend never schedules a Timer at all (every write "flushes"
      // synchronously), so this test only has to care about the reactive
      // rebuild, which is what it's actually testing.
      await AllBox.initWithMemoryBackendForTesting(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));
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
}
