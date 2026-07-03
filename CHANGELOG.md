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
* `write()`/`writeAndFlush()` now validate that the value is JSON-encodable
  synchronously and throw `ArgumentError` immediately, instead of only
  failing silently later inside the debounced flush.
* No Web support in this release (documented limitation). Not isolate-safe
  (documented limitation).
