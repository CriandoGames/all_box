## Unreleased

Web support, plus a breaking change: the reactive layer is gone.

The public core import stays exactly the same
(`import 'package:all_box/all_box.dart';`) — platform selection happens
internally via Dart's conditional imports (`dart.library.io` /
`dart.library.js_interop`), not via anything a consumer imports or
configures.

**Breaking: reactivity removed.** `all_box` no longer has any
listener/reactive API. Removed:

- `AllBox.listenKey`/`removeListenKey`/`listenAll` (the core no longer
  notifies anything on `write()`/`remove()`/`erase()`).
- `AllBoxListenable<T>` and `AllBoxBuilder<T>` (the Flutter reactive
  layer), and the `package:all_box/all_box_flutter.dart` entrypoint
  entirely — there is now a single entrypoint,
  `package:all_box/all_box.dart`, for every platform including Flutter.
- The `.val()` extension on `String` (`AllBoxValue`/`AllBoxValueExtension`),
  which existed only to read/write through the now-removed reactive layer.
- `test/all_box_flutter_test.dart` (it only tested the removed reactive
  layer); the `erase()`/`remove()`/`.val()` tests in the remaining suites
  were updated to no longer assert on listener notifications.

**Why:** this keeps `all_box` a plain synchronous key-value store with no
opinion on state management, and makes the package pure Dart — it no
longer depends on the Flutter SDK at all (`pubspec.yaml` no longer
declares a `flutter:` dependency; `flutter_test` was replaced by
`package:test` in the package's own test suite).

**Migration:** call `write()`/`writeAndFlush()`/`erase()` as before, then
update your UI the same way you would for any other synchronous,
non-reactive storage — e.g. `setState` right after the call in a
`StatefulWidget`, or by wiring `all_box` into a `ChangeNotifier` you own,
`all_observer`, or whatever state-management approach your app already
uses. There is no drop-in replacement inside `all_box` itself for
`AllBoxBuilder`/`AllBoxListenable`/`listenKey`/`listenAll`/`.val()`.

- **Web storage**, automatic and `path`-free: `AllBox.init('settings')` (no
  `path`) now works on Web, backed by `window.localStorage` via pure
  `dart:js_interop` static interop — never `dart:html` (which blocks
  `dart2wasm` compilation) and no new dependency (`package:web` wasn't
  needed). On IO platforms, behavior is unchanged: `path` is still how you
  tell `AllBox` where `<container>.db` lives.
- **New `AllBox.memory(container, {initialData})`**: promoted, non-deprecated
  replacement for `initWithMemoryBackendForTesting()` (which still works,
  now as a thin `@Deprecated` wrapper around `memory()`).
- **New public types**: `AllBoxStorage` (the storage seam — IO, Web,
  in-memory, or your own), `AllBoxPersistMode` (`save`/`flush` durability
  tiers), `AllBoxStorageException` (unsupported platform, missing `path` on
  IO, JSON encoding failures, Web storage quota/availability errors). All
  advanced/optional — everyday code never touches them.
- New test suites: `test/all_box_memory_storage_test.dart`,
  `test/all_box_platform_storage_test.dart`,
  `test/web/all_box_web_storage_test.dart` (fake-backed, runs on the VM),
  and `test/web/all_box_web_storage_browser_test.dart` (real
  `window.localStorage`, `@TestOn('browser')`-gated — run with
  `dart test -p chrome test/web/all_box_web_storage_browser_test.dart`).
  Added large-payload/large-volume coverage (5,000-key round-trips, ~200 KB
  single values) across IO, memory and Web storage.

**Breaking changes — and why they're mostly not a problem in practice:**

- `AllBox.init()` return type changed from `Future<void>` to
  `Future<AllBox>` (it now returns the initialized instance, so
  `final box = await AllBox.init('settings');` works directly, instead of
  needing a separate `AllBox('settings')` call afterwards). This is
  source-breaking only for code that explicitly typed the return value as
  `Future<void>` or passed `AllBox.init` itself as a
  `Future<void> Function(...)` callback/tear-off — a plain
  `await AllBox.init(...)` call site (the documented, common usage) is
  unaffected.
- `path` changed from a required named parameter to an optional one
  (`String? path`). This is **not** breaking on its own — relaxing
  required → optional never breaks a call site that already passed `path`.
  It does change the failure mode on IO when `path` is omitted: previously
  a compile-time "missing required argument" error, now a runtime
  `AllBoxStorageException` with a clear message. Code that already
  compiled before is unaffected either way.
- The minimum Dart SDK constraint moved from `>=3.0.0` to `>=3.3.0`
  (required by the `dart:js_interop` extension types used in the Web
  storage backend). This **is** breaking for any consumer pinned to a Dart
  SDK older than 3.3.0 — `pub get`/`flutter pub get` will fail to resolve
  this version for them.
- No import statement changed for consumers: `dart:io`, `dart:js_interop`
  and the conditional-import platform selection are entirely internal to
  the package (`lib/src/core/storage/platform/`); `package:all_box/all_box.dart`
  is still the only import needed, on every platform.

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
