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
[Known limitations](https://github.com/CriandoGames/all_box/blob/main/README.md#️-known-limitations-documented-not-hidden)
in the README.

## Flush coordination

The debounce/coalescing/serialized-flush-queue logic lives once, inside
`AllBox` itself, and works against any `AllBoxStorage` implementation (IO,
Web, in-memory, or a custom one passed via `storage:`) — it isn't
duplicated per backend. This guarantees there are never two concurrent
writes in flight against the same container, even if `flushNow()` or
`writeAndFlush()` is called while a debounced flush is still pending.

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

---

Back to [README](https://github.com/CriandoGames/all_box/blob/main/README.md).
