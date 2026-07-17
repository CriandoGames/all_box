🇧🇷 [Português](https://github.com/CriandoGames/all_box/blob/main/documentation/pt-BR/architecture.md) | 🇺🇸 English

# Internal architecture

Implementation details behind `all_box`'s guarantees. Everyday usage of the
package never requires reading this — it exists for contributors and for
anyone auditing the crash-safety and Web-storage claims made in the
[README](https://github.com/CriandoGames/all_box/blob/main/README.md).

## Crash-safety: write-ahead + atomic rename

On IO platforms, every disk write follows the same pipeline:

1. The new content is written to a `.tmp` file first (write-ahead).
2. Once that write completes, an atomic rename replaces the main file
   (`<container>.db`) with the `.tmp` file's content.
3. A `.bak` copy of the last known-good state is kept separately.

Because the rename is atomic (on POSIX filesystems), the main file is never
observed in a partially-written state — a crash mid-write leaves either the
old `.db` intact or the fully-written new one, never a mix of both.

### Two-stage read error handling

On read, UTF-8 decoding errors and `jsonDecode` errors are treated as
distinct failure stages. Each stage falls back to `.bak` before giving up
and starting from an empty container.

If `.db`/`.bak` files exist but neither can be decoded, the IO backend emits
a debug-only diagnostic and starts with an empty in-memory container. The
corrupted files are not deleted during `init()`; they remain available for
manual inspection until a later successful save replaces them through the
normal write-ahead pipeline. This keeps corruption visible in debug builds
without adding another public recovery API.

### `File.rename` portability

The atomic swap relies on `File.rename` semantics. On POSIX
(Linux/macOS/Android/iOS), renaming over an existing file is atomic. On
Windows, behavior can vary between Dart SDK versions — see
[Known limitations](#known-limitations) below.

## Durability tiers

`write()`, `writeAndSave()`, and `writeAndFlush()` all update memory
synchronously; they differ only in what the returned (or absent) `Future`
waits for before persistence is considered done:

- **`write()`** is fire-and-forget: the change is scheduled into the
  debounced flush queue (see below) and the call returns immediately.
- **`writeAndSave()`** waits for the OS write to complete, without forcing
  `fsync` — survives an app crash, but not necessarily a power loss (the OS
  may still be holding the write in its page cache).
- **`writeAndFlush()`** waits for `fsync` on IO — the strongest guarantee
  the platform can offer, surviving power loss as well as an app crash.

On Web, `writeAndSave()` and `writeAndFlush()` behave identically: a
`localStorage.setItem` call is already synchronous, so there's no
meaningful distinction to make on top of it.

## Flush coordination

The debounce/coalescing/serialized-flush-queue logic lives once, inside
`AllBox` itself, and works against any `AllBoxStorage` implementation (IO,
Web, in-memory, or a custom one passed via `storage:`) — it isn't
duplicated per backend. This guarantees there are never two concurrent
writes in flight against the same container, even if `flushNow()` or
`writeAndFlush()` is called while a debounced flush is still pending.

The first `write()` of a burst arms a single debounce `Timer`
(`flushDelay`, 100ms by default); every subsequent `write()` inside that
window just marks the container dirty and rides the already-armed timer,
so a burst of writes still produces exactly one flush.

Flush failures are reported through `onPersistenceError` when the caller
provided one at `AllBox.init()`. This matters most for debounced `write()`,
because there is no returned `Future` to complete with an error. Awaited
APIs (`writeAndSave()`, `writeAndFlush()`, `flushNow()`) still rethrow the
storage failure through their returned `Future`; the callback is an
additional reporting hook, not a replacement for normal `Future` errors.

## `initialData` semantics

`initialData` passed to `AllBox.init()` is only applied on a genuine first
run. The check is based on whether `<container>.db`/`<container>.bak`
already exist on disk — not on in-memory state — so a container emptied by
a previous `erase()` still counts as "already persisted" and the seed is
never reapplied over it. When it does apply, the seed is persisted
immediately (bypassing the debounce window), so it survives a crash right
after the app's first launch.

Initialization is serialized per container. Concurrent calls with
equivalent options share the same in-flight initialization `Future`.
Concurrent calls with conflicting `path`, `storage`, `initialData`,
`flushDelay`, `onPersistenceError`, or `validateContainerName` are rejected
with a `StateError` instead of letting one configuration win
non-deterministically.

When first-run seeding fails to persist, initialization is rolled back:
the container is left uninitialized, in-memory data is cleared, and a later
`init()` call can retry from a clean state.

## Lifecycle and deletion

`close({flushPending})` closes a container and removes its singleton from
the internal registry. With the default `flushPending: true`, pending
in-memory data is flushed before the backend storage is closed. With
`flushPending: false`, pending debounced writes are discarded.

`destroy()` cancels pending debounce work, deletes persisted data through
the backend, closes the backend storage, and removes the singleton from the
registry. On IO, the backend deletes `.db`, `.tmp`, and `.bak`; on Web it
removes the browser storage key. This is logical deletion, not secure
physical wiping.

## Container names on IO

For compatibility, container names are permissive by default. Existing apps
that use names like `user/cache` keep working.

When `validateContainerName: true` is passed to `AllBox.init()` on IO, the
built-in IO storage validates the name before any file access. Strict mode
accepts only letters, numbers, `.`, `_`, and `-`, and rejects empty names,
`.`/`..`, path separators, drive separators, trailing dots/spaces, and
Windows reserved device names such as `CON`, `NUL`, `COM1`, and `LPT1`.
This opt-in mode is useful for apps that want one cross-platform filename
policy and no path-like container names.

## Inspector snapshots

`AllBoxInspector.snapshot()` and `snapshotOf()` return point-in-time
snapshots. Snapshot entries are deeply copied and made unmodifiable for
maps and lists, so mutating a value after the snapshot is created does not
change the snapshot already handed to tooling.

Inspector backend reporting is intentionally compatibility-first. The public
`AllBoxBackendKind.web` enum value remains the stable category for browser
storage, including the internal IndexedDB testbed and migration wrapper.
Tools that need the concrete implementation can read the optional
`backendDetail` field (`localStorage`, `indexedDB`, or
`indexedDBMigration`) from the snapshot object/JSON instead of switching on
new enum values. Mutation extension events keep the same kind and payload.

## Debug-only serialization warning

`write()`/`writeAndSave()`/`writeAndFlush()` call `jsonEncode` on the value
on the spot, in debug builds only, and log a warning if it isn't
serializable — but never throw or block the write. The value is still
written to memory normally; if it truly can't be encoded, the failure
resurfaces later, silently, inside the flush. This is intentional: a
production app shouldn't crash because a caller stored a `DateTime` or an
`enum` without `toJson()` — it should just be told about it, loudly, while
developing.

## Web storage backend

The Web backend is built on `dart:js_interop` static interop, never
`dart:html`. `dart:html` blocks `dart2wasm` compilation, so relying on it
would rule out WASM builds; `dart:js_interop` extension types (stabilized
in Dart 3.3) avoid that constraint while still calling
`window.localStorage` directly, with no extra dependency (`package:web`
isn't needed).

Platform selection between the IO and Web storage backends happens via
Dart's conditional imports (`dart.library.io` / `dart.library.js_interop`)
in `lib/src/core/storage/platform/`. Consumers never see this — the public
entrypoint (`package:all_box/all_box.dart`) is the same import on every
platform.

`save` and `flush` behave identically on Web: there's no `fsync`
equivalent, since a `localStorage.setItem` call is already synchronous.

The current built-in Web backend is a **Window-only** backend. It is wired
to `window.localStorage`, which MDN documents as a property of `Window`, and
the Web Storage API is exposed through `Window.localStorage`/
`Window.sessionStorage`. It is not advertised as a Worker or Service Worker
backend. A future Worker-compatible backend should use a different storage
contract, most likely IndexedDB, instead of pretending `localStorage` works
everywhere.

Because the Web backend stores one full JSON snapshot per container, it does
not synchronize concurrent writers across multiple browser tabs. The
singleton registry only protects one Dart isolate/window. Two tabs writing
from stale snapshots can still lose data. This is a documented architectural
limitation until a revision/conflict protocol and a backend suitable for
cross-context coordination are designed.

An internal IndexedDB storage testbed exists behind
`AllBoxIndexedDbStorage` and `AllBoxBrowserIndexedDbDriver`, with VM/fake
and real-Chrome regression tests. It is intentionally not wired into
`AllBox.init()` yet: the default Web backend remains `window.localStorage`
while the full migration/default-switch plan is validated. Inspector
compatibility for the inactive backends is covered below; safe multi-tab
behavior still needs a separate design.

The localStorage -> IndexedDB migration path is also implemented as an
inactive internal wrapper (`AllBoxIndexedDbMigrationStorage`). Its tests
cover legacy localStorage reads, IndexedDB-first precedence, migration that
removes the legacy copy only after a successful IndexedDB write, IndexedDB
failure fallback to localStorage, and delete behavior across both stores.
Inspector compatibility is covered separately: all Web-family backends still
report `backend: web`, with `backendDetail` identifying the concrete backend.

The internal IndexedDB browser driver uses schema version 1 with a single
`containers` object store. After opening a database it verifies that this
store exists, so an incompatible database is reported with a clear schema
diagnostic instead of failing later during a transaction. Browser regression
tests also cover `versionchange` auto-close behavior and blocked deletion
errors. This hardening still does not make IndexedDB the default Web backend.

## Benchmarks

`tool/web_storage_benchmark.dart` provides a lightweight benchmark report
for the pure-Dart `AllBoxWebStorage` encode/decode path against a fake
synchronous browser storage. It covers 100/1,000/5,000 keys, 100 KB/500 KB/1
MB values, burst writes, and multiple containers:

```bash
dart run tool/web_storage_benchmark.dart
```

`test/web/all_box_web_storage_browser_benchmark_test.dart` complements that
with an optional real-browser report against `window.localStorage`:

```bash
dart test -p chrome test/web/all_box_web_storage_browser_benchmark_test.dart --reporter expanded
```

Both commands deliberately print measurements as local comparison reports
rather than enforcing machine-dependent thresholds. Use repeated runs on the
same machine/browser before making performance claims about
`window.localStorage` blocking behavior.

## Known limitations

- **Web storage (`localStorage`) has real limits.** There's no `fsync`
  equivalent (see above). Storage is scoped per browser *origin* (scheme +
  host + port), so `http://localhost:3000` and `http://localhost:4000` see
  completely different storages during local development. Size limits vary
  by browser (commonly a few MB per origin) and aren't enforced or
  reported by `AllBox` ahead of time — a write past the limit throws an
  `AllBoxStorageException`. Data isn't encrypted: don't store secrets or
  sensitive data in a Web container without encrypting it yourself first.
  Not recommended for large volumes of data.
- **The built-in Web backend is Window-only and not multi-tab safe.**
  It uses `window.localStorage` and keeps synchronization only inside the
  current Dart isolate/window. Web Workers, Service Workers, and safe
  multi-tab writes require a different backend/contract, such as a future
  IndexedDB-backed design.
- **Not isolate-safe.** Each `AllBox` keeps its state in memory in the
  isolate where it was initialized; there's no cross-isolate
  synchronization. If you use multiple isolates (e.g. `compute()`,
  background isolates), each one needs its own `init()` and they won't see
  each other's writes until they re-read from disk.
- **`File.rename` for the atomic swap is OS-dependent.** On POSIX
  (Linux/macOS/Android/iOS), renaming over an existing file is atomic. On
  Windows, behavior can vary between Dart SDK versions; test this scenario
  specifically if your app runs on Windows desktop.

---

Back to [README](https://github.com/CriandoGames/all_box/blob/main/README.md).
