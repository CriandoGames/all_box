## 0.3.0

Performance release — additive API only, no new dependencies for the
package itself, on-disk format unchanged.

- **New `writeAndSave()`:** intermediate durability tier. Completes once
  the OS write finishes (survives an app crash — the same guarantee class
  as `Hive.put`), without the fsync cost of `writeAndFlush()` (the only
  tier that survives power loss). Keeps the full write-ahead +
  atomic-rename pipeline. Durability ladder: `write()` →
  `writeAndSave()` → `writeAndFlush()`. When both tiers coalesce into the
  same flush, the strongest requirement wins.

- **Flush path ~2× less I/O:** the pre-flush backup (`.db` → `.bak`) is now
  a metadata-only `rename` instead of a full byte-for-byte `copy`.
  Crash-safety guarantees are unchanged: at any instant either `.db` or
  `.bak` holds a complete known-good version, and `init()` already falls
  back to `.bak`.
- **Flush coalescing:** N concurrent `writeAndFlush()` calls now collapse
  into at most 2 real disk writes (one in-flight + one queued) instead of N
  sequential full-file writes. Each caller's `Future` still only completes
  once its value is durably on disk.
- **`write()` hot path:** the debounce timer is now armed once per burst
  instead of being cancelled and recreated on every `write()` (the timer
  churn used to cost more than the in-memory map update itself). Side
  benefit: continuous writes can no longer starve the flush — it now fires
  at most `flushDelay` after the *first* write of a burst.
- New test suite `test/flush_performance_test.dart` (21 tests): db/bak
  invariants, simulated crash windows, coalescing contracts, timer
  semantics, durability round-trips, and randomized mutation stress.
- New on-device benchmark screen in the example app (`example/lib/benchmark/`)
  comparing all_box vs Hive and SharedPreferences with the same loops in
  the same session (multiple rounds, median reported) — including honest
  per-lib durability-guarantee caveats. Competitor dependencies live only
  in the example app. GetStorage is not in the measured comparison: its
  `write()` Future resolves without waiting for any disk write (there is
  no API in it that does), so there is nothing comparable to measure; it
  remains covered in the qualitative comparison docs.
- Updated comparison docs and charts with numbers measured on a real
  device in profile mode.
- `benchmark/benchmark_test.dart`: the package benchmark now runs via
  `flutter test benchmark/benchmark_test.dart` (`dart run` never worked —
  the package imports `flutter/foundation`).

## 0.2.1

Documentation-only release — no code changes to `lib/`, no breaking
changes, no new external dependencies.

- Restructured `README.md`/`README.pt-BR.md` into the same landing-page
  format used by `all_observer` (table of contents, feature highlights,
  compact comparison table, "when to use it" section, "other packages by
  us" table, EN ⇄ PT-BR language switch links).
- Added `documentation/en/comparison.md` and
  `documentation/pt-BR/comparison.md`: a detailed, factual comparison
  against GetStorage, Hive, Isar, and SharedPreferences, including a
  performance benchmark table (1,000 operations: in-memory write, sync
  read, durable disk write).
- Added a new comparison benchmark chart
  (`doc/comparison_benchmark_en.png` / `doc/comparison_benchmark_pt-BR.png`)
  plotting all five solutions on a log scale.
- Fixed the test-count badge (18 → 19) to match `test/all_box_test.dart`.

## 0.2.0

* `AllBox.init()` gains an `initialData` parameter, seeding default values
  on a genuine first run only (checked via the presence of
  `<container>.db`/`<container>.bak` on disk, not via in-memory state, so a
  container emptied by a previous `erase()` is correctly never reseeded).
  The seed is persisted immediately, bypassing the debounce window.
* `write()`/`writeAndFlush()` no longer throw `ArgumentError` for a
  non-JSON-encodable value. In debug builds only, they now log a loud
  `debugPrint` warning (wrapped in ANSI red) instead, matching
  `GetStorage`'s permissive behavior — the write still goes through in
  memory either way.

## 0.1.0

Initial release.

* Synchronous in-memory reads (`read`, `readOrDefault`, `hasData`,
  `getKeys`, `getValues`).
* Optimistic, debounced writes (`write`) and forced-flush writes
  (`writeAndFlush`); `flushNow()` to bypass the debounce window on demand
  (e.g. `AppLifecycleState.paused`).
* One file per container, JSON-encoded via `dart:convert`.
* Write-ahead crash-safety: writes land on `<container>.tmp` first, then an
  atomic rename replaces `<container>.db`; the previous good file is kept
  as `<container>.bak`.
* Two-stage read error handling (UTF-8 decoding vs. JSON parsing), each
  falling back to `<container>.bak`, then to an empty container — `init()`
  never throws on a corrupted file.
* Serialized flush queue: concurrent `writeAsString` calls on the same file
  are never allowed to race.
* `path` is a required parameter of `AllBox.init()` — no internal
  `path_provider` dependency, no plugin-path `MissingPluginException` risk.
* `listenKey`/`removeListenKey`, `listenAll` (returns a dispose callback),
  `erase()` notifying every previously-existing key's listeners.
* `AllBoxListenable<T>` (`ChangeNotifier` + `ValueListenable<T?>`) and
  `AllBoxBuilder<T>` widget — pure-Flutter reactive layer.
* Optional `.val()` extension on `String`, DI-free.
* `AllBox.initWithMemoryBackendForTesting()` — pure in-memory backend for
  apps/packages that consume `all_box` to unit/widget-test their own code,
  with no real disk I/O and no real `Timer` scheduled on `write()`.
* `write()`/`writeAndFlush()` validated that the value was JSON-encodable
  synchronously and threw `ArgumentError` immediately if not (superseded in
  0.2.0 by a debug-only warning — see above).
* No Web support in this release (documented limitation). Not isolate-safe
  (documented limitation).
