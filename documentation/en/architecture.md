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

## `initialData` semantics

`initialData` passed to `AllBox.init()` is only applied on a genuine first
run. The check is based on whether `<container>.db`/`<container>.bak`
already exist on disk — not on in-memory state — so a container emptied by
a previous `erase()` still counts as "already persisted" and the seed is
never reapplied over it. When it does apply, the seed is persisted
immediately (bypassing the debounce window), so it survives a crash right
after the app's first launch.

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
