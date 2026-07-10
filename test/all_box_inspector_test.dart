// Tests for AllBoxInspector (package:all_box/all_box.dart): the
// debug/profile-only, read-only introspection surface added to support
// external tooling (e.g. a DevTools extension) without reintroducing a
// listener/reactive API.
//
// **PT-BR:** Testes do AllBoxInspector: a superfície de introspecção
// somente-leitura, restrita a debug/profile, adicionada para dar suporte a
// ferramentas externas (ex.: uma extensão de DevTools) sem reintroduzir uma
// API de listener/reatividade.

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

Future<Directory> _tempDir(String label) async {
  final dir = await Directory.systemTemp.createTemp('all_box_inspector_${label}_');
  addTearDown(() async {
    AllBox.resetInstanceForTesting(label);
    if (dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  });
  return dir;
}

void main() {
  group('AllBoxInspector.snapshot / snapshotOf', () {
    test('reports a memory-backed container with its entries', () async {
      const container = 'inspector_memory';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(
        container,
        initialData: <String, dynamic>{'a': 1, 'b': 'two'},
      );
      box.write('c', true);

      final snap = AllBoxInspector.snapshotOf(container);
      expect(snap, isNotNull);
      expect(snap!.container, container);
      expect(snap.isInitialized, isTrue);
      expect(snap.backend, AllBoxBackendKind.memory);
      expect(snap.pendingFlush, isFalse);
      expect(snap.entries, <String, dynamic>{'a': 1, 'b': 'two', 'c': true});
      expect(snap.keys, containsAll(<String>['a', 'b', 'c']));
      expect(snap.length, 3);
      expect(snap.approximateSizeBytes, greaterThan(0));

      expect(
        AllBoxInspector.snapshot().map((s) => s.container),
        contains(container),
      );
    });

    test('reports an IO-backed container and pendingFlush while debounced',
        () async {
      const container = 'inspector_io';
      final dir = await _tempDir(container);

      final box = await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(milliseconds: 200),
      );
      box.write('key', 'value');

      final snap = AllBoxInspector.snapshotOf(container)!;
      expect(snap.backend, AllBoxBackendKind.io);
      // write() is debounced: right after the call, the flush is still
      // pending.
      expect(snap.pendingFlush, isTrue);

      await box.flushNow();
      final afterFlush = AllBoxInspector.snapshotOf(container)!;
      expect(afterFlush.pendingFlush, isFalse);
    });

    test('placeholder (never initialized) container is reported as such',
        () {
      const container = 'inspector_placeholder';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      // Constructing via the factory alone does not initialize it.
      AllBox(container);

      final snap = AllBoxInspector.snapshotOf(container)!;
      expect(snap.isInitialized, isFalse);
      expect(snap.entries, isEmpty);
      expect(snap.backend, AllBoxBackendKind.unsupported);
    });

    test('unknown container returns null', () {
      expect(
        AllBoxInspector.snapshotOf('never_seen_this_container'),
        isNull,
      );
    });

    test('snapshot entries are a read-only copy, not a live view', () async {
      const container = 'inspector_copy';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(
        container,
        initialData: <String, dynamic>{'k': 1},
      );

      final snap = AllBoxInspector.snapshotOf(container)!;
      box.write('k', 2);

      expect(snap.entries['k'], 1, reason: 'snapshot must not mutate live');
      expect(box.read<int>('k'), 2);
      expect(() => snap.entries['k'] = 3, throwsUnsupportedError);
    });
  });

  group('AllBoxInspector.snapshotAsJson / snapshotOfAsJson', () {
    test('round-trips through jsonDecode with the same shape as toJson()',
        () async {
      const container = 'inspector_json';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      await AllBox.memory(
        container,
        initialData: <String, dynamic>{'a': 1, 'nested': <String, dynamic>{'x': true}},
      );

      final single = AllBoxInspector.snapshotOfAsJson(container);
      final decodedSingle = jsonDecode(single) as Map<String, dynamic>;
      expect(decodedSingle['container'], container);
      expect(decodedSingle['backend'], 'memory');
      expect(decodedSingle['entries'], <String, dynamic>{
        'a': 1,
        'nested': <String, dynamic>{'x': true},
      });

      final all = jsonDecode(AllBoxInspector.snapshotAsJson()) as List<dynamic>;
      expect(
        all.cast<Map<String, dynamic>>().map((m) => m['container']),
        contains(container),
      );
    });

    test('unknown container -> literal "null"', () {
      expect(
        AllBoxInspector.snapshotOfAsJson('never_seen_this_container_json'),
        'null',
      );
    });

    test('non-JSON-encodable value becomes a placeholder, not a throw', () async {
      const container = 'inspector_json_non_encodable';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);
      // DateTime is not directly JSON-encodable by jsonEncode.
      box.write('when', DateTime(2026, 7, 10));

      final json = AllBoxInspector.snapshotOfAsJson(container);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final entries = decoded['entries'] as Map<String, dynamic>;
      expect(entries['when'], startsWith('<non-JSON-encodable:'));
    });
  });
}
