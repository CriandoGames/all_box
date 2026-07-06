🇧🇷 [Português](https://github.com/CriandoGames/all_box/blob/main/documentation/pt-BR/comparison.md) | 🇺🇸 English

# How `all_box` compares

A factual, non-marketing comparison against other Flutter key-value storage
solutions. None of these are "bad" — they solve for different priorities.
The performance numbers below come from an in-house comparison (`all_box`
vs. popular solutions), run locally; treat them as order-of-magnitude
indicators, not an official benchmark of any of the libraries named here.

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| External dependencies | Zero | Zero | `hive` | `isar`, `isar_flutter_libs` (+ codegen) | Platform plugin (`shared_preferences`) |
| Code generation | None | None | Optional (custom type adapters) | Required (`isar_generator`/`build_runner`) for typed models | None |
| Data model | Flat key-value, JSON-encodable | Flat key-value | Typed/`Map`-like boxes, supports custom objects | Object-oriented database, typed schema, indexes and queries | Flat key-value, primitive types only |
| Reads | Synchronous, 100% in memory after `init()` | Synchronous, 100% in memory after `init()` | Synchronous (box already open in memory) | Synchronous for simple reads; queries are async | Async (`await SharedPreferences.getInstance()`), cached afterward |
| Writes | Optimistic + debounced; `writeAndFlush()` to confirm on disk | Optimistic, no exposed configurable debounce | Async by default (`box.put`), with manual `flush()` | Async, with explicit transactions | Async, a full file rewrite per call on some platforms |
| Crash-safety | Write-ahead (`.tmp`) + atomic rename + fallback `.bak`, documented | Not publicly documented at the same level of detail | Internal WAL/compaction (Hive 2), version-dependent | WAL via its own engine (Isar Core, Rust) | Entirely dependent on the platform's native implementation |
| Storage `path` | Explicit, required in `init()` — never resolved internally | Resolved internally (uses `path_provider`/`GetStorage` defaults) | Resolved by the caller (`Hive.init(path)`) | Resolved by the caller (`Isar.open(directory: ...)`) | Resolved internally by the platform |
| Reactivity | `AllBoxListenable`/`AllBoxBuilder`, 100% Flutter (`ChangeNotifier`/`ValueListenable`) | `GetBuilder`/`Obx` (coupled to the GetX ecosystem) | `ValueListenableBuilder` over `box.listenable()` | `watchObject`/`watchLazy` (streams) | None — needs your own wrapper |
| Web support | No (v1) | Yes | Yes | Yes (via WASM) | Yes |
| Learning curve | Low | Low | Medium | Medium–high (schema, queries, codegen) | Low |
| Scope | Key-value storage + reactivity only | Storage + some UI utilities (GetX) | Box/object-oriented storage | Full embedded database (queries, indexes, relations) | Thin wrapper over native platform preferences |

## Performance (1,000 operations, local run)

![Performance comparison: all_box vs. GetStorage, Hive, Isar and SharedPreferences](../../doc/comparison_benchmark_en.png)

| Solution | Write (memory) | Read (synchronous) | Durable write (disk) |
| --- | --- | --- | --- |
| **all_box** | 5 ms | 2 ms | 1,200 ms |
| GetStorage | 6 ms | 2 ms | 1,100 ms |
| Hive | 15 ms | 3 ms | 15 ms |
| Isar | 8 ms | 5 ms | 8 ms |
| SharedPreferences | 120 ms | 40 ms | 120 ms |

How to read this table:

- **Write (memory)** and **Read (synchronous)** measure only the path that
  never touches disk — this is where `all_box` and `GetStorage` win by
  reading/writing straight from an in-memory `Map`, with no schema/index
  overhead.
- **Durable write (disk)** measures the cost of guaranteeing each of the
  1,000 writes is physically on disk before moving on. `all_box` and
  `GetStorage` pay this price by rewriting the whole container file on
  every confirmed write — safe, but expensive if you confirm to disk on
  every single write instead of using the optimistic/debounced path. Hive
  and Isar are cheaper here because they use an append-only log/WAL format
  instead of rewriting everything. In practice, `all_box`'s recommended
  path is the optimistic `write()` (the "memory" number above, not the disk
  one), with `writeAndFlush()`/`flushNow()` reserved for the few moments
  you need a real, immediate guarantee (e.g. `AppLifecycleState.paused`).
- **SharedPreferences** is consistently the slowest across all three
  columns because every read/write crosses a platform channel
  (`MethodChannel`) — overhead that `all_box`, `GetStorage`, `Hive`, and
  `Isar` avoid by keeping hot state in Dart memory.

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
complex Dart objects with minimal manual serialization, or need to run in
the browser. `all_box` only handles plain JSON-encodable values (mapped to
a single JSON file per container) — no adapters, no Web support in this v1.

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
Web support and custom type adapters (Hive), a full embedded database with
queries/indexes/relations (Isar), or just the Flutter ecosystem's most
"standard" platform wrapper (SharedPreferences) for a small app that needs
no built-in reactivity at all.

---

Back to [README](https://github.com/CriandoGames/all_box/blob/main/README.md).
