// Tests for the two flush-path performance optimizations:
//
//  A) Backup via `rename` (metadata-only) instead of a full byte `copy`.
//     These tests pin down that the crash-safety contract is unchanged:
//     after every flush, `.db` holds the newest version and `.bak` holds
//     the previous known-good one, and every simulated crash window
//     recovers to a complete version (never a half-written file).
//
//  B) Flush coalescing: N concurrent `writeAndFlush()` calls collapse into
//     at most 2 real disk writes (one in-flight + one queued), while each
//     caller's `Future` still only completes once *its* value is on disk.
//
// **PT-BR:** Testes das duas otimizações do caminho de flush:
//
//  A) Backup via `rename` (só metadata) em vez de `copy` byte a byte.
//     Estes testes fixam que o contrato de crash-safety não mudou: depois
//     de cada flush, `.db` tem a versão mais nova e `.bak` a anterior
//     íntegra, e toda janela de crash simulada recupera uma versão
//     completa (nunca um arquivo pela metade).
//
//  B) Coalescing de flush: N `writeAndFlush()` concorrentes colapsam em no
//     máximo 2 gravações reais (uma em andamento + uma na fila), com o
//     `Future` de cada caller ainda só completando quando o valor *dele*
//     está em disco.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test/test.dart';

import 'package:all_box/all_box.dart';

/// Each test gets its own temp directory and container name, so containers
/// never collide with the static singleton cache across tests in the same
/// isolate.
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

Map<String, dynamic> _readJson(File file) {
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

void main() {
  group('backup via rename: on-disk state after flushes', () {
    test('first flush ever creates .db, leaves no .tmp and no .bak', () async {
      const container = 'rename_first_flush';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndFlush('a', 1);

      expect(File('${dir.path}/$container.db').existsSync(), isTrue);
      expect(File('${dir.path}/$container.tmp').existsSync(), isFalse,
          reason: 'the write-ahead temp file must be renamed away');
      expect(File('${dir.path}/$container.bak').existsSync(), isFalse,
          reason: 'there was no previous version to preserve yet');
      expect(_readJson(File('${dir.path}/$container.db')), {'a': 1});
    });

    test('.bak always holds the previous version, .db the newest', () async {
      const container = 'rename_bak_is_previous';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndFlush('v', 1);
      await box.writeAndFlush('v', 2);

      expect(_readJson(File('${dir.path}/$container.db')), {'v': 2});
      expect(_readJson(File('${dir.path}/$container.bak')), {'v': 1});

      await box.writeAndFlush('v', 3);

      expect(_readJson(File('${dir.path}/$container.db')), {'v': 3});
      expect(_readJson(File('${dir.path}/$container.bak')), {'v': 2});
    });

    test('db/bak invariant holds across many sequential durable writes',
        () async {
      const container = 'rename_invariant_loop';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      for (var i = 1; i <= 20; i++) {
        await box.writeAndFlush('i', i);
        final db = _readJson(File('${dir.path}/$container.db'));
        expect(db['i'], i, reason: '.db must hold the newest version');
        if (i > 1) {
          final bak = _readJson(File('${dir.path}/$container.bak'));
          expect(bak['i'], i - 1,
              reason: '.bak must hold exactly the previous version');
        }
        expect(File('${dir.path}/$container.tmp').existsSync(), isFalse,
            reason: 'no .tmp may be left behind after a completed flush');
      }
    });

    test('erase() + flushNow() persists {} and .bak keeps pre-erase data',
        () async {
      const container = 'rename_erase';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndFlush('keep', 'me');
      box.erase();
      await box.flushNow();

      expect(_readJson(File('${dir.path}/$container.db')), isEmpty);
      expect(_readJson(File('${dir.path}/$container.bak')), {'keep': 'me'});
    });
  });

  group('backup via rename: simulated crash windows', () {
    // Window 1: process died after writing .tmp but before any rename.
    // .db (old) is untouched; the stale .tmp must simply be ignored.
    test('crash after tmp write, before renames → old .db wins', () async {
      const container = 'crash_window_1';
      final dir = await _tempDir(container);

      await File('${dir.path}/$container.db').writeAsString('{"v":"old"}');
      await File('${dir.path}/$container.tmp').writeAsString('{"v":"new"}');

      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      expect(box.read<String>('v'), 'old',
          reason: 'a stale .tmp must never be promoted to real data');
    });

    // Window 2 (the one new crash window introduced by rename-as-backup):
    // process died between `rename db → bak` and `rename tmp → db`.
    // .db is momentarily absent; .bak holds the previous complete version.
    test('crash between the two renames → recovers previous version from .bak',
        () async {
      const container = 'crash_window_2';
      final dir = await _tempDir(container);

      await File('${dir.path}/$container.bak').writeAsString('{"v":"old"}');
      await File('${dir.path}/$container.tmp').writeAsString('{"v":"new"}');
      // No .db at all: exactly the state left by a crash mid-swap.

      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      expect(box.read<String>('v'), 'old',
          reason: 'must fall back to the complete .bak, not lose everything');
    });

    // Window 3: .db was fully swapped in, then the process died. Trivially
    // fine, pinned here for completeness.
    test('crash right after the swap → new .db wins over older .bak',
        () async {
      const container = 'crash_window_3';
      final dir = await _tempDir(container);

      await File('${dir.path}/$container.db').writeAsString('{"v":"new"}');
      await File('${dir.path}/$container.bak').writeAsString('{"v":"old"}');

      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      expect(box.read<String>('v'), 'new');
    });

    test('corrupted .db after crash → falls back to .bak written by rename',
        () async {
      const container = 'crash_corrupted_db';
      final dir = await _tempDir(container);

      // First, produce a real .bak through the actual flush pipeline.
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);
      await box.writeAndFlush('v', 'good');
      await box.writeAndFlush('v', 'newer');
      AllBox.resetInstanceForTesting(container);

      // Then corrupt .db in place, as a torn write / disk fault would.
      await File('${dir.path}/$container.db')
          .writeAsBytes(<int>[0xFF, 0x00, 0xDE, 0xAD]);

      await AllBox.init(container, path: dir.path);
      final box2 = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      expect(box2.read<String>('v'), 'good',
          reason: '.bak produced by the rename path must be a valid fallback');
    });
  });

  group('flush coalescing', () {
    test('N concurrent writeAndFlush() collapse into at most 2 disk writes',
        () async {
      const container = 'coalesce_burst';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      const n = 50;
      final futures = <Future<void>>[
        for (var i = 0; i < n; i++) box.writeAndFlush('key_$i', i),
      ];
      await Future.wait(futures);

      expect(box.flushCountForTesting, lessThanOrEqualTo(2),
          reason: 'a same-turn burst must coalesce, not flush $n times');

      // Every caller's data must still be on disk.
      final persisted = _readJson(File('${dir.path}/$container.db'));
      for (var i = 0; i < n; i++) {
        expect(persisted['key_$i'], i);
      }
    });

    test('every coalesced Future completes (none is dropped)', () async {
      const container = 'coalesce_all_complete';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      var completed = 0;
      final futures = <Future<void>>[
        for (var i = 0; i < 25; i++)
          box.writeAndFlush('k$i', i).then((_) => completed++),
      ];
      await Future.wait(futures);

      expect(completed, 25);
    });

    test('awaited (serial) writeAndFlush calls are NOT coalesced', () async {
      const container = 'coalesce_serial_unaffected';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      for (var i = 0; i < 5; i++) {
        await box.writeAndFlush('i', i);
      }

      expect(box.flushCountForTesting, 5,
          reason: 'each awaited call must still be its own durable write');
      expect(_readJson(File('${dir.path}/$container.db')), {'i': 4});
    });

    test("writeAndFlush contract: value is on disk when the Future completes",
        () async {
      const container = 'coalesce_contract';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      // Fire a burst without awaiting, then await ONE arbitrary member of
      // it: at that moment, that caller's value must already be persisted.
      // ignore: unawaited_futures
      box.writeAndFlush('a', 1);
      // ignore: unawaited_futures
      box.writeAndFlush('b', 2);
      final chosen = box.writeAndFlush('c', 3);

      await chosen;

      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted['c'], 3,
          reason: "the awaited caller's value must be durable on completion");
      expect(persisted['a'], 1,
          reason: 'earlier coalesced values ride along in the same snapshot');
      expect(persisted['b'], 2);
    });

    test('a second burst after the first is fully persisted too', () async {
      const container = 'coalesce_two_bursts';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await Future.wait(<Future<void>>[
        for (var i = 0; i < 10; i++) box.writeAndFlush('first_$i', i),
      ]);
      final flushesAfterFirst = box.flushCountForTesting;

      await Future.wait(<Future<void>>[
        for (var i = 0; i < 10; i++) box.writeAndFlush('second_$i', i),
      ]);

      expect(box.flushCountForTesting - flushesAfterFirst,
          lessThanOrEqualTo(2));

      final persisted = _readJson(File('${dir.path}/$container.db'));
      for (var i = 0; i < 10; i++) {
        expect(persisted['first_$i'], i);
        expect(persisted['second_$i'], i);
      }
    });

    test('coalescing works with remove() and erase() in the same burst',
        () async {
      const container = 'coalesce_mutations';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndFlush('stale', 'x');

      // Mixed mutation burst, all in the same event-loop turn.
      // ignore: unawaited_futures
      box.writeAndFlush('a', 1);
      box.remove('stale');
      final last = box.writeAndFlush('b', 2);
      await last;

      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted.containsKey('stale'), isFalse,
          reason: 'the remove() must be reflected in the coalesced snapshot');
      expect(persisted['a'], 1);
      expect(persisted['b'], 2);
    });

    test('debounced write() followed by writeAndFlush() lands in one flush',
        () async {
      const container = 'coalesce_debounce_then_flush';
      final dir = await _tempDir(container);
      await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(seconds: 5), // never fires in this test
      );
      final box = AllBox(container);

      box.write('debounced', true); // scheduled, but debounce is 5s away
      await box.writeAndFlush('flushed', true);

      expect(box.flushCountForTesting, 1,
          reason: 'the flush must carry the debounced data too — no second '
              'disk write needed');

      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted['debounced'], isTrue);
      expect(persisted['flushed'], isTrue);
    });

    test('a failing flush does not wedge the queue for later flushes',
        () async {
      const container = 'coalesce_failure_recovery';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      // A non-JSON-encodable value makes jsonEncode throw inside
      // _writeToDisk, rejecting that flush's Future.
      box.write('bad', DateTime.now());
      await expectLater(box.flushNow(), throwsA(isA<Object>()));

      // The pipeline must recover: fix the data and flush again.
      box.remove('bad');
      await expectLater(box.writeAndFlush('good', 1), completes);

      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted['good'], 1);
    });
  });

  group('writeAndSave (intermediate durability, no fsync)', () {
    test('value is written to the container file when the Future completes',
        () async {
      const container = 'save_basic';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndSave('k', 'v');

      expect(_readJson(File('${dir.path}/$container.db')), {'k': 'v'});
      expect(File('${dir.path}/$container.tmp').existsSync(), isFalse);
    });

    test('keeps the db/bak invariant, same as writeAndFlush', () async {
      const container = 'save_invariant';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndSave('v', 1);
      await box.writeAndSave('v', 2);

      expect(_readJson(File('${dir.path}/$container.db')), {'v': 2});
      expect(_readJson(File('${dir.path}/$container.bak')), {'v': 1});
    });

    test('coalesces with writeAndFlush in the same burst (strongest '
        'durability wins, single write covers both)', () async {
      const container = 'save_mixed_burst';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      // Same-turn burst mixing both durability tiers.
      // ignore: unawaited_futures
      box.writeAndSave('saved', 1);
      final flushed = box.writeAndFlush('flushed', 2);
      await flushed;

      expect(box.flushCountForTesting, lessThanOrEqualTo(2));
      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted['saved'], 1);
      expect(persisted['flushed'], 2);
    });

    test('round-trips after reset + re-init (data actually reached the OS)',
        () async {
      const container = 'save_roundtrip';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      await box.writeAndSave('answer', 42);

      AllBox.resetInstanceForTesting(container);
      await AllBox.init(container, path: dir.path);
      final reloaded = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      expect(reloaded.read<int>('answer'), 42);
    });

    test('throws StateError before init, like the other write APIs',
        () async {
      const container = 'save_uninitialized';
      addTearDown(() => AllBox.resetInstanceForTesting(container));
      final box = AllBox(container);

      expect(() => box.writeAndSave('k', 1), throwsStateError);
    });
  });

  group('scheduleFlush timer semantics (armed once per burst)', () {
    test('writes during the armed window ride the same timer: one flush, '
        'all data included', () async {
      const container = 'timer_single_burst';
      final dir = await _tempDir(container);
      await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(milliseconds: 100),
      );
      final box = AllBox(container);

      box.write('a', 1); // arms the timer
      await Future<void>.delayed(const Duration(milliseconds: 30));
      box.write('b', 2); // inside the window: must NOT re-arm nor be lost
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(box.flushCountForTesting, 1);
      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted, {'a': 1, 'b': 2},
          reason: 'the flush copies the live map at fire time, so writes '
              'made while the timer was armed must be included');
    });

    test('continuous writes cannot starve the flush indefinitely', () async {
      const container = 'timer_no_starvation';
      final dir = await _tempDir(container);
      await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(milliseconds: 50),
      );
      final box = AllBox(container);

      // Writes every 20ms for ~300ms. A classic debounce (re-armed on every
      // write) would never fire during this loop; the armed-once timer must
      // fire at most flushDelay after the FIRST write of each burst.
      for (var i = 0; i < 15; i++) {
        box.write('tick', i);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(box.flushCountForTesting, greaterThanOrEqualTo(2),
          reason: 'flushes must keep happening under continuous writes');
      final persisted = _readJson(File('${dir.path}/$container.db'));
      expect(persisted['tick'], 14, reason: 'last value must be durable');
    });

    test('flushNow() cancels the armed timer (no duplicate flush after)',
        () async {
      const container = 'timer_cancelled_by_flushnow';
      final dir = await _tempDir(container);
      await AllBox.init(
        container,
        path: dir.path,
        flushDelay: const Duration(milliseconds: 100),
      );
      final box = AllBox(container);

      box.write('a', 1); // arms the timer
      await box.flushNow(); // flushes and cancels it
      expect(box.flushCountForTesting, 1);

      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(box.flushCountForTesting, 1,
          reason: 'the cancelled timer must not fire a redundant flush');
    });
  });

  group('durability round-trips (regression net for the rename path)', () {
    test('nested/unicode data survives flush → reset → re-init', () async {
      const container = 'roundtrip_types';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      final payload = <String, dynamic>{
        'string': 'olá, açaí! 🥋',
        'int': 42,
        'double': 3.14,
        'bool': true,
        'null': null,
        'list': <dynamic>[1, 'two', false, null],
        'nested': <String, dynamic>{
          'level2': <String, dynamic>{
            'level3': <dynamic>['deep', 'values'],
          },
        },
      };
      for (final entry in payload.entries) {
        box.write(entry.key, entry.value);
      }
      await box.flushNow();

      AllBox.resetInstanceForTesting(container);
      await AllBox.init(container, path: dir.path);
      final reloaded = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      expect(reloaded.read<String>('string'), 'olá, açaí! 🥋');
      expect(reloaded.read<int>('int'), 42);
      expect(reloaded.read<double>('double'), 3.14);
      expect(reloaded.read<bool>('bool'), isTrue);
      expect(reloaded.hasData('null'), isTrue);
      expect(reloaded.read<List<dynamic>>('list'), [1, 'two', false, null]);
      expect(
        (reloaded.read<Map<String, dynamic>>('nested')?['level2']
            as Map<String, dynamic>?)?['level3'],
        ['deep', 'values'],
      );
    });

    test('a large box (5.000 keys) flushes and reloads intact', () async {
      const container = 'roundtrip_large';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      for (var i = 0; i < 5000; i++) {
        box.write('key_$i', 'value_$i');
      }
      await box.flushNow();

      AllBox.resetInstanceForTesting(container);
      await AllBox.init(container, path: dir.path);
      final reloaded = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      expect(reloaded.getKeys().length, 5000);
      expect(reloaded.read<String>('key_0'), 'value_0');
      expect(reloaded.read<String>('key_2500'), 'value_2500');
      expect(reloaded.read<String>('key_4999'), 'value_4999');
    });

    test('a large single value (~200 KB string) flushes and reloads intact',
        () async {
      const container = 'roundtrip_large_value';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      final bigValue = 'x' * (200 * 1024);
      await box.writeAndFlush('blob', bigValue);

      AllBox.resetInstanceForTesting(container);
      await AllBox.init(container, path: dir.path);
      final reloaded = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      expect(reloaded.read<String>('blob'), bigValue);
    });

    test('reading 5,000 keys back after init stays fast (regression guard, '
        'not a strict benchmark)', () async {
      const container = 'roundtrip_large_read_perf';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      for (var i = 0; i < 5000; i++) {
        box.write('key_$i', i);
      }
      await box.flushNow();

      AllBox.resetInstanceForTesting(container);
      await AllBox.init(container, path: dir.path);
      final reloaded = AllBox(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final stopwatch = Stopwatch()..start();
      var sum = 0;
      for (var i = 0; i < 5000; i++) {
        sum += reloaded.read<int>('key_$i') ?? 0;
      }
      stopwatch.stop();

      expect(sum, greaterThan(0));
      // Generous ceiling for CI variance — reads are synchronous, in-memory
      // Map lookups after init, so this should be near-instant; this is a
      // regression guard against read<T>() accidentally becoming O(n) per
      // call, not a precise timing assertion.
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test('randomized mutation stress: disk always matches a shadow map',
        () async {
      const container = 'roundtrip_stress';
      final dir = await _tempDir(container);
      await AllBox.init(container, path: dir.path);
      final box = AllBox(container);

      final random = Random(2026); // deterministic
      final shadow = <String, dynamic>{};

      for (var round = 0; round < 10; round++) {
        // A burst of random mutations…
        final futures = <Future<void>>[];
        for (var op = 0; op < 30; op++) {
          final key = 'k${random.nextInt(20)}';
          switch (random.nextInt(3)) {
            case 0:
              final value = random.nextInt(1000);
              shadow[key] = value;
              box.write(key, value);
            case 1:
              final value = 'v${random.nextInt(1000)}';
              shadow[key] = value;
              futures.add(box.writeAndFlush(key, value));
            case 2:
              shadow.remove(key);
              box.remove(key);
          }
        }
        // …then settle everything durably and compare with the shadow map.
        await Future.wait(futures);
        await box.flushNow();

        final persisted = _readJson(File('${dir.path}/$container.db'));
        expect(persisted, equals(shadow),
            reason: 'round $round: disk state diverged from the shadow map');
      }
    });
  });
}
