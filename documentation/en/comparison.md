🇧🇷 [Português](https://github.com/CriandoGames/all_box/blob/main/documentation/pt-BR/comparison.md) | 🇺🇸 English

# How `all_box` compares

A factual, non-marketing comparison against other Flutter key-value storage
solutions. None of these are "bad" — they solve for different priorities.
The performance numbers below were measured **on-device**, via the
"Storage comparison" screen in this repository's `example/` app (Android,
profile mode, same session and same loops for every lib) — anyone can
reproduce them with `cd example && flutter run --profile`. Treat them as
order-of-magnitude indicators, not an official benchmark of any of the
libraries named here.

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| External dependencies | Zero | Zero | `hive` | `isar`, `isar_flutter_libs` (+ codegen) | Platform plugin (`shared_preferences`) |
| Code generation | None | None | Optional (custom type adapters) | Required (`isar_generator`/`build_runner`) for typed models | None |
| Data model | Flat key-value, JSON-encodable | Flat key-value | Typed/`Map`-like boxes, supports custom objects | Object-oriented database, typed schema, indexes and queries | Flat key-value, primitive types only |
| Reads | Synchronous, 100% in memory after `init()` | Synchronous, 100% in memory after `init()` | Synchronous (box already open in memory) | Synchronous for simple reads; queries are async | Async (`await SharedPreferences.getInstance()`), cached afterward |
| Writes | Optimistic + debounced; `writeAndSave()` (waits for the OS) and `writeAndFlush()` (fsync) to confirm on disk | Optimistic, no exposed configurable debounce; no API waits for disk | Async by default (`box.put`), with manual `flush()` | Async, with explicit transactions | Async, a full file rewrite per call on some platforms |
| Crash-safety | Write-ahead (`.tmp`) + atomic rename + fallback `.bak`, documented | Not publicly documented at the same level of detail | Internal WAL/compaction (Hive 2), version-dependent | WAL via its own engine (Isar Core, Rust) | Entirely dependent on the platform's native implementation |
| Storage `path` | Explicit, required in `init()` — never resolved internally | Resolved internally (uses `path_provider`/`GetStorage` defaults) | Resolved by the caller (`Hive.init(path)`) | Resolved by the caller (`Isar.open(directory: ...)`) | Resolved internally by the platform |
| Reactivity | `AllBoxListenable`/`AllBoxBuilder`, 100% Flutter (`ChangeNotifier`/`ValueListenable`) | `GetBuilder`/`Obx` (coupled to the GetX ecosystem) | `ValueListenableBuilder` over `box.listenable()` | `watchObject`/`watchLazy` (streams) | None — needs your own wrapper |
| Web support | Yes (`window.localStorage` via `dart:js_interop`) | Yes | Yes | Yes (via WASM) | Yes |
| Learning curve | Low | Low | Medium | Medium–high (schema, queries, codegen) | Low |
| Scope | Key-value storage + reactivity only | Storage + some UI utilities (GetX) | Box/object-oriented storage | Full embedded database (queries, indexes, relations) | Thin wrapper over native platform preferences |

## Performance (measured on-device, profile mode)

![Performance comparison: all_box vs. Hive and SharedPreferences](../../doc/comparison_benchmark_en.png)

Android (build AE3A.240806.036), profile mode, "Storage comparison" screen
in the `example/` app, median of 5 rounds (memory) / 3 (disk). Average
cost per operation (lower is better):

| Scenario | all_box | Hive | SharedPreferences |
| --- | --- | --- | --- |
| Optimistic write (memory), 10,000 ops | **0.3 µs** | 5.3 µs | 87.2 µs |
| Synchronous read, 10,000 ops | **0.2 µs** | 0.9 µs | 0.2 µs |
| Confirmed write (no fsync), 200 ops | 28.9 ms | **5.6 ms** | 30.1 ms |
| Durable write with fsync, 200 ops | 52.6 ms | — no API | — no API |
| Burst of 200 `write()` + 1 flush | **323.7 µs** | 4,532.5 µs | 25,199.0 µs |

How to read this table:

- **Optimistic write and read** are `all_box`'s strong points: direct
  in-memory `HashMap` access — ~17× faster than Hive on writes, a
  technical tie with SharedPreferences on reads.
- **Burst + 1 flush** is `all_box`'s real-world usage pattern (optimistic
  debounced writes, one flush at the end): 200 writes persisted in 64 ms
  total, ~14× faster than Hive and ~78× faster than SharedPreferences on
  the same loop.
- **Confirmed write** uses each lib's own "persisted" contract, with no
  fsync anywhere (`writeAndSave()` for `all_box`, `put()` for Hive,
  `setInt()` for SharedPreferences). Hive wins this row, and the reason is
  structural: it *appends* a few bytes to a log, while `all_box` rewrites
  the container file with write-ahead + atomic rename — more file
  operations per confirmation, in exchange for a file that can never be
  left half-written. If you confirm to disk on every write in a loop, Hive
  is better; `all_box`'s recommended path is the optimistic/debounced one
  (rows 1 and 5).
- **Durable write with fsync** has a single bar because only `all_box`
  offers this guarantee (`writeAndFlush()`): when the `Future` completes,
  the data survives power loss, not just an app crash. None of the others
  have an equivalent API.
- **GetStorage** is not in the measured table for a technical reason: its
  `write()` Future resolves after scheduling a microtask, without waiting
  even for the buffered OS write — there is no API in GetStorage that
  waits for data to reach disk, so there is nothing comparable to measure
  in the confirmation/durability rows. The qualitative comparison below
  still covers it.
- **Isar** was left out of the on-device measurement (it requires a native
  engine + codegen, which would complicate the example app); the
  qualitative comparison below still stands.
- Debug-mode numbers are not comparable — `all_box` in particular pays a
  debug-only `jsonEncode` guard per `write()` that does not exist in
  release/profile.

## GetStorage

A sync/JSON key-value store very close in philosophy to `all_box` — same
idea of synchronous reads post-init and optimistic writes. The main design
difference is `path`: `GetStorage` resolves its storage directory
internally, while `all_box` requires you to pass `path` explicitly to
`init()`, avoiding by construction the plugin/Activity resolution bugs
reported against libraries that resolve the path on their own. `all_box`
also explicitly documents its crash-safety strategy (write-ahead + atomic
rename + `.bak`); treat this as a documentation/transparency difference,
not necessarily a claim about `GetStorage`'s internal robustness.

## Hive

A box-based key-value database with its own file format, native Web
support, and adapters for custom types. Best choice when you need to store
complex Dart objects with minimal manual serialization. `all_box` only
handles plain JSON-encodable values (mapped to a single JSON file per
container on IO, or a `localStorage` key on Web) — no adapters.

## Isar

A full embedded database: typed schema, indexes, composite queries, and
relations, built on its own Rust engine. Best choice when your app actually
needs a database — complex queries, large record volumes, relations
between entities — rather than a handful of preferences/flags. `all_box`
intentionally doesn't try to be a database; it's a flat key-value store for
settings, flags, and small app state.

## SharedPreferences

Flutter's "official" platform wrapper over `UserDefaults` (iOS/macOS),
`SharedPreferences` (Android), and equivalents on other platforms.
Ubiquitous and simple, but async from end to end and limited to primitive
types (no nested lists/maps without manual serialization). `all_box` covers
the same core use case (settings, flags, small app state) with synchronous
reads post-init and a built-in reactive layer — trading the per-platform
native implementation for a single JSON file managed entirely by Dart.

## Why choose `all_box`

Reach for it when you want simple key-value storage — settings, flags,
small app state — with synchronous reads after boot, optimistic writes with
an explicit opt-in to durable confirmation, a reactive layer with no
external state-management dependency, and full, explicit control over
where your data lives on disk (`path` required, never resolved by internal
magic).

Reach for something else when you specifically need what it specializes in:
custom type adapters for complex objects (Hive), a full embedded database
with queries/indexes/relations (Isar), or just the Flutter ecosystem's most
"standard" platform wrapper (SharedPreferences) for a small app that needs
no built-in reactivity at all.

---

Back to [README](https://github.com/CriandoGames/all_box/blob/main/README.md).
