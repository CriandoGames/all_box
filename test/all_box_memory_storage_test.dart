// Tests for AllBox.memory() (backed by AllBoxMemoryStorage): no real disk
// I/O, no browser storage, no real Timer. Covers the same day-to-day
// surface as the IO-backed tests in test/all_box_core_test.dart, but
// against the in-memory storage specifically.
//
// **PT-BR:** Testes do AllBox.memory() (apoiado no AllBoxMemoryStorage): sem
// I/O real em disco, sem storage de navegador, sem Timer real. Cobre a
// mesma superfície do dia a dia dos testes apoiados em IO em
// test/all_box_core_test.dart, mas especificamente contra o storage em
// memória.

import 'package:flutter_test/flutter_test.dart';

import 'package:all_box/all_box.dart';

void main() {
  group('AllBox.memory()', () {
    test('seeds initialData and reads/writes work synchronously', () async {
      const container = 'memory_seed_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(
        container,
        initialData: {'seeded': 'value'},
      );

      expect(box.read<String>('seeded'), 'value');

      box.write('counter', 1);
      expect(box.read<int>('counter'), 1);
    });

    test('read/readOrDefault/hasData/getKeys/getValues', () async {
      const container = 'memory_read_api_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);

      expect(box.read<String>('missing'), isNull);
      expect(box.readOrDefault<String>('missing', 'fallback'), 'fallback');
      expect(box.hasData('missing'), isFalse);

      box.write('a', 1);
      box.write('b', 'two');

      expect(box.hasData('a'), isTrue);
      expect(box.getKeys(), containsAll(<String>['a', 'b']));
      expect(box.getValues(), containsAll(<dynamic>[1, 'two']));
    });

    test('remove() deletes a key and notifies its listeners', () async {
      const container = 'memory_remove_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);
      box.write('k', 'v');

      var notified = 0;
      box.listenKey('k', () => notified++);

      box.remove('k');

      expect(box.hasData('k'), isFalse);
      expect(notified, 1);

      // Removing an already-absent key is a no-op and must not notify.
      box.remove('k');
      expect(notified, 1);
    });

    test('erase() clears everything and notifies every prior key + global',
        () async {
      const container = 'memory_erase_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);
      box.write('a', 1);
      box.write('b', 2);

      var aNotified = 0;
      var bNotified = 0;
      var globalNotified = 0;
      box.listenKey('a', () => aNotified++);
      box.listenKey('b', () => bNotified++);
      box.listenAll(() => globalNotified++);

      box.erase();

      expect(box.getKeys(), isEmpty);
      expect(aNotified, 1);
      expect(bNotified, 1);
      expect(globalNotified, 1);
    });

    test('writeAndSave and writeAndFlush both complete without a real Timer',
        () async {
      const container = 'memory_write_variants_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);

      await box.writeAndSave('save_key', 'save_value');
      expect(box.read<String>('save_key'), 'save_value');

      await box.writeAndFlush('flush_key', 'flush_value');
      expect(box.read<String>('flush_key'), 'flush_value');

      await box.flushNow();
    });

    test('does not schedule any real Timer on write', () async {
      const container = 'memory_no_timer_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);

      box.write('a', 1);
      box.write('b', 2);

      // Every write "flushes" synchronously against the in-memory storage,
      // so there's no debounce window to wait out — if this were a
      // disk/Web-backed container, this assertion would need a real delay.
      expect(box.flushCountForTesting, 2);
    });

    test('listenKey stops firing after removeListenKey', () async {
      const container = 'memory_listen_key_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);

      var callCount = 0;
      void callback() => callCount++;

      box.listenKey('k', callback);
      box.write('k', 1);
      expect(callCount, 1);

      box.removeListenKey('k', callback);
      box.write('k', 2);
      expect(callCount, 1, reason: 'listener must not fire after removal');
    });

    test('listenAll dispose function removes the global listener', () async {
      const container = 'memory_listen_all_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);

      var callCount = 0;
      final dispose = box.listenAll(() => callCount++);

      box.write('x', 1);
      expect(callCount, 1);

      dispose();
      box.write('x', 2);
      expect(callCount, 1,
          reason: 'global listener must not fire after dispose');
    });

    test('resetInstanceForTesting clears the cached singleton', () async {
      const container = 'memory_reset_test';

      await AllBox.memory(container, initialData: {'k': 'v'});
      AllBox.resetInstanceForTesting(container);

      final box = await AllBox.memory(container);
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      // A fresh memory() after reset must not see the previous instance's
      // in-memory data.
      expect(box.hasData('k'), isFalse);
    });

    test('calling memory() again for an already-initialized container is a '
        'no-op', () async {
      const container = 'memory_reinit_noop_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final first = await AllBox.memory(container, initialData: {'k': 'v'});
      final second = await AllBox.memory(container, initialData: {'k': 'ignored'});

      expect(identical(first, second), isTrue);
      expect(second.read<String>('k'), 'v');
    });

    test('a large box (5,000 keys) reads/writes intact via memory storage',
        () async {
      const container = 'memory_large_volume_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);

      for (var i = 0; i < 5000; i++) {
        box.write('key_$i', 'value_$i');
      }

      expect(box.getKeys().length, 5000);
      expect(box.read<String>('key_0'), 'value_0');
      expect(box.read<String>('key_2500'), 'value_2500');
      expect(box.read<String>('key_4999'), 'value_4999');

      // Every write "flushed" synchronously into the in-memory snapshot, so
      // a fresh flushNow() must see the same data (no debounce backlog).
      await box.flushNow();
      expect(box.read<String>('key_4999'), 'value_4999');
    });

    test('reading 5,000 keys back stays fast (regression guard, not a '
        'strict benchmark)', () async {
      const container = 'memory_large_read_perf_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      final box = await AllBox.memory(container);
      for (var i = 0; i < 5000; i++) {
        box.write('key_$i', i);
      }

      final stopwatch = Stopwatch()..start();
      var sum = 0;
      for (var i = 0; i < 5000; i++) {
        sum += box.read<int>('key_$i') ?? 0;
      }
      stopwatch.stop();

      expect(sum, greaterThan(0));
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });
  });

  group('deprecated initWithMemoryBackendForTesting alias', () {
    test('still works and delegates to memory()', () async {
      const container = 'memory_deprecated_alias_test';
      addTearDown(() => AllBox.resetInstanceForTesting(container));

      // ignore: deprecated_member_use
      await AllBox.initWithMemoryBackendForTesting(
        container,
        initialValues: {'seeded': 'value'},
      );
      final box = AllBox(container);

      expect(box.read<String>('seeded'), 'value');
    });
  });
}
