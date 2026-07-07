<h1 align="center">all_box</h1>

<p align="center">
🇧🇷 <a href="https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md">Português</a> | 🇺🇸 English
</p>

<p align="center">
  <a href="https://pub.dev/packages/all_box"><img src="https://img.shields.io/pub/v/all_box.svg?label=pub.dev" alt="pub version"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/likes/all_box?label=likes" alt="pub likes"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/points/all_box?label=pub%20points" alt="pub points"></a>
  <a href="https://github.com/CriandoGames/all_box/blob/main/LICENSE"><img src="https://img.shields.io/github/license/CriandoGames/all_box" alt="license"></a>
  <img src="https://img.shields.io/badge/tests-19-brightgreen" alt="19 tests">
</p>

<p align="center">
💡 Synchronous, lightweight and fast key-value storage, pure Dart at its core — with crash-safe writes and an optional Flutter reactive layer.
</p>

## Table of contents

- [Features](#-features)
- [Installing](#-installing)
- [Example App](#-example-app)
- [Features in detail](#️-features-in-detail)
- [Usage examples](#-usage-examples)
- [API](#-api)
- [Design decisions](#️-design-decisions)
- [Known limitations](#️-known-limitations-documented-not-hidden)
- [Comparison](#-comparison)
- [When to use it (and when not to)](#-when-to-use-it-and-when-not-to)
- [Testing](#-testing)
- [Documentation](#-documentation)
- [Other packages by us](#-other-packages-by-us)

## 🚀 Features

- 🪶 **100% synchronous reads.** After `init()`, every `read<T>()` is
  synchronous — no `Future`, no `FutureBuilder`, no I/O wait on the read
  path.
- 🧱 **Pure Dart core, Flutter layer optional.** `package:all_box/all_box.dart`
  has no Flutter import at all. `AllBoxListenable` and `AllBoxBuilder` — built
  directly on `ChangeNotifier` and `ValueListenable`, no external
  state-management dependency — live in the separate
  `package:all_box/all_box_flutter.dart` import.
- 🛡️ **Real crash-safety.** Every write lands on a `.tmp` file first, then
  an atomic rename replaces the main file (`.db`); a `.bak` of the last good
  state is kept separately, with automatic two-stage fallback (UTF-8
  decoding errors and `jsonDecode` errors).
- 📍 **Explicit `path`, never resolved internally.** `AllBox` never imports
  `path_provider` nor resolves any directory — whoever calls `init()`
  decides where the container lives. This avoids, by construction, the
  plugin/Activity resolution bugs that affect libraries that resolve the
  path by default.
- ⚡ **Optimistic, debounced writes**, with `writeAndFlush()`/`flushNow()`
  for the moments you need a real, immediate on-disk guarantee.
- 🧪 **In-memory backend for testing.**
  `AllBox.initWithMemoryBackendForTesting()` runs with no real I/O and no
  real `Timer`, safe for `testWidgets`.

Part of the `all_*` family of open-source packages alongside
[`all_validations_br`](https://pub.dev/packages/all_validations_br)
(Brazilian validations, utilities and encryption) and `all_image_compress`
(image compression).

## 📦 Installing

```
flutter pub add all_box
```

```yaml
dependencies:
  all_box: ^0.2.1
```

Dart-only code (no Flutter widgets) needs just the core:

```dart
import 'package:all_box/all_box.dart';

await AllBox.init('settings', path: dir.path);
final box = AllBox('settings');
box.write('name', 'Carlos');
final name = box.read<String>('name');
```

Flutter apps that also want the reactive layer (`AllBoxListenable`,
`AllBoxBuilder`) import the Flutter entrypoint instead — it re-exports
everything from the core, so a single import is enough:

```dart
import 'package:all_box/all_box_flutter.dart';

AllBoxBuilder<String>(
  keyName: 'name',
  builder: (context, value) => Text(value ?? ''),
);
```

## 📱 Example App

The `example/` directory contains an interactive Flutter app (`CounterPage`)
demonstrating the whole day-to-day public surface: optimistic `write()` vs.
`writeAndFlush()`, a reactive `AllBoxBuilder<T>`, `listenAll` for global
side effects (a `SnackBar`), and `flushNow()` fired on
`AppLifecycleState.paused`.

To run it:

```bash
cd example
flutter pub get
flutter run
```

## ⚙️ Features in detail

### Initialization

```dart
import 'package:all_box/all_box.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // AllBox never resolves its own directory — you do, after the binding is
  // ready. Any path strategy works.
  final dir = await getApplicationDocumentsDirectory();
  await AllBox.init('my_container', path: dir.path);

  runApp(const MyApp());
}
```

### Seeding data on first run (`initialData`)

```dart
await AllBox.init(
  'settings',
  path: dir.path,
  initialData: const {
    'darkMode': false,
    'onboarded': false,
  },
);
```

`initialData` only applies on a genuine first run — when the container
doesn't yet have `<container>.db`/`<container>.bak` on disk. It's persisted
immediately (it doesn't wait for the debounce), so it survives a crash
right after the app's first launch. If the container already existed
before — even as an empty `{}` left by a previous `erase()` — `initialData`
is ignored and whatever is on disk wins.

### Reading and writing (every read is synchronous)

```dart
final box = AllBox('my_container');

box.write('name', 'Carlos');           // optimistic: memory + listeners
                                        // update immediately, disk follows
                                        // ~100ms later (debounced)

String? name = box.read<String>('name');
String safeName = box.readOrDefault<String>('name', 'anonymous');

await box.writeAndFlush('name', 'Carlos'); // waits for disk confirmation

box.remove('name');
box.erase(); // clears everything and notifies every listener that existed

await box.flushNow(); // forces a flush now, e.g. on AppLifecycleState.paused
```

### Listening for changes

```dart
box.listenKey('name', () => print('name changed'));
box.removeListenKey('name', callback);

final dispose = box.listenAll(() => print('container changed'));
// later
dispose();
```

### Reactive widgets, no external state-management dependency

Requires `package:all_box/all_box_flutter.dart` instead of the core-only
`package:all_box/all_box.dart`:

```dart
import 'package:all_box/all_box_flutter.dart';

AllBoxBuilder<int>(
  keyName: 'counter',
  builder: (context, value) => Text('${value ?? 0}'),
)
```

Or build your own `ValueListenable` with `AllBoxListenable<T>`:

```dart
final counter = AllBoxListenable<int>('counter');
ValueListenableBuilder<int?>(
  valueListenable: counter,
  builder: (context, value, _) => Text('${value ?? 0}'),
);
```

### DI-free `.val()` helper (optional)

An opt-in mini state-manager, with no dependency-injection coupling at all:

```dart
final darkMode = 'darkMode'.val(false);
print(darkMode.value);
darkMode.value = true;
```

## 🧪 Usage examples

### Value with a safe fallback

```dart
final box = AllBox('settings');
final theme = box.readOrDefault<String>('theme', 'light');
// Returns 'light' if the 'theme' key doesn't exist yet
```

### Optimistic write vs. confirmed write

```dart
box.write('score', 100);              // memory updated immediately
await box.writeAndFlush('score', 100); // only returns after disk confirms
```

### Reacting to a single key inside a widget

```dart
class DarkModeSwitch extends StatelessWidget {
  const DarkModeSwitch({super.key});

  @override
  Widget build(BuildContext context) {
    return AllBoxBuilder<bool>(
      keyName: 'darkMode',
      builder: (context, value) => Switch(
        value: value ?? false,
        onChanged: (v) => AllBox().write('darkMode', v),
      ),
    );
  }
}
```

### Clearing a container and reacting globally

```dart
final dispose = box.listenAll(() => print('something changed in "settings"'));

box.erase(); // fires the listener above exactly once

dispose();
```

### Container introspection

```dart
box.hasData('theme');   // true / false
box.getKeys();          // every key ever written
box.getValues();        // every value ever written
```

### Persisting app state when paused

```dart
class _MyAppState extends State<MyApp> with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      AllBox('my_container').flushNow();
    }
  }
}
```

## 📚 API

Everything below `AllBoxListenable`/`AllBoxBuilder` is core
(`package:all_box/all_box.dart`); those two live in
`package:all_box/all_box_flutter.dart`.

| Member | Description |
| --- | --- |
| `AllBox([container])` | Factory constructor; returns a singleton per container name. |
| `static AllBox.init(container, {required path, flushDelay, initialData})` | Loads `container` from disk into memory. `path` is required — see below. `initialData` seeds default values, but only on a genuine first run. |
| `T? read<T>(key)` / `T readOrDefault<T>(key, fallback)` | Synchronous reads. |
| `void write(key, value)` | Optimistic, debounced write. In debug mode, warns (via a red `debugPrint`) if `value` isn't JSON-encodable, but never throws. |
| `Future<void> writeAndFlush(key, value)` | Writes and waits for disk confirmation. Same serialization warning as `write()`. |
| `void remove(key)` / `void erase()` | Removes a key / clears everything (`erase()` notifies every previously-existing key's listeners). |
| `Future<void> flushNow()` | Forces an immediate flush, bypassing the debounce window. |
| `listenKey(key, cb)` / `removeListenKey(key, cb)` | Per-key listeners. |
| `VoidCallback listenAll(cb)` | Global listener; returns a dispose function. |
| `hasData(key)`, `getKeys()`, `getValues()` | Introspection. |
| `AllBoxListenable<T>` | `ChangeNotifier` + `ValueListenable<T?>` for a single key. |
| `AllBoxBuilder<T>` | Widget that rebuilds when `keyName` changes. |
| `'key'.val<T>(default)` | Optional DI-free mini state-manager handle. |

### Why is `path` a required parameter of `init()`?

`AllBox` **never** imports `path_provider` (nor resolves any directory)
internally. The caller always decides where the container lives. It's a
deliberate design choice, not an oversight — see the section below.

## 🛠️ Design decisions

- **Explicit, required `path` in `init()`.** `all_box` never resolves any
  directory internally — whoever calls `init()` always supplies `path`,
  avoiding any plugin resolution inside the library.
- **`initialData` only applies on a genuine first run.** The check is done
  via the presence of `<container>.db`/`<container>.bak` on disk, not
  in-memory state — a container emptied by `erase()` still has a persisted
  `{}`, so it's not considered a "first run" and the seed isn't reapplied
  over it.
- **Crash-safety via write-ahead + atomic rename.** Every disk write lands
  on a `.tmp` file first, then an atomic rename replaces the main file
  (`.db`); a `.bak` of the last good state is kept separately.
- **Two-stage read error handling.** UTF-8 decoding errors and
  `jsonDecode` errors are treated as distinct failure stages, each falling
  back to `.bak` before giving up and starting empty.
- **Serialized flush queue.** There are never two concurrent writes on the
  same file, even if `flushNow()`/`writeAndFlush()` is called while a
  debounced flush is still in flight.
- **Reproducible benchmark.** Performance numbers measured on-device and
  maintained in this repository — see the [Comparison](#-comparison)
  section; reproduce them yourself with the example app
  (`cd example && flutter run --profile`, then tap the ⚡ icon) or run the
  package's own micro-benchmark with
  `flutter test benchmark/benchmark_test.dart`.
- **Debug-only serialization warning, not an exception.**
  `write()`/`writeAndFlush()` call `jsonEncode` on the value on the spot,
  debug-only, and emit a red `debugPrint` if it isn't serializable — but
  never throw or block the write (same permissive behavior as
  `GetStorage`). The value is still written to memory normally; if it
  truly can't be encoded, the failure only resurfaces silently deep inside
  the flush.
- **No Web support in this v1** (see limitations below).

## ⚠️ Known limitations (documented, not hidden)

- **No Web support in this v1.** If it's ever added, it should use
  `package:web` via conditional imports — **never** `dart:html`, since
  `dart:html` blocks WASM compilation (`dart2wasm`).
- **Not isolate-safe.** Each `AllBox` keeps its state in memory in the
  isolate where it was initialized; there's no cross-isolate
  synchronization. If you use multiple isolates (e.g. `compute()`,
  background isolates), each one needs its own `init()` and they won't see
  each other's writes until they re-read from disk.
- **`File.rename` for the atomic swap is OS-dependent.** On POSIX
  (Linux/macOS/Android/iOS), renaming over an existing file is atomic. On
  Windows, behavior can vary between Dart SDK versions; test this scenario
  specifically if your app runs on Windows desktop.

## ⚖️ Comparison

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| Reads | Synchronous, in memory | Synchronous, in memory | Synchronous (open box) | Synchronous (simple) / async (queries) | Async |
| Storage `path` | Explicit, required | Resolved internally | Resolved by caller | Resolved by caller | Resolved by platform |
| Documented crash-safety | Write-ahead + atomic rename + `.bak` | Not documented at the same level | Internal WAL/compaction | WAL via its own engine | Platform-dependent |
| Web support | No (v1) | Yes | Yes | Yes | Yes |
| Scope | Key-value + reactivity only | Storage + some UI utils (GetX) | Box-oriented storage | Full database | Platform wrapper |

![Performance comparison: all_box vs. Hive and SharedPreferences, measured on-device in profile mode](doc/comparison_benchmark_en.png)

Measured on-device (Android, profile mode) via the example app's "Storage
comparison" screen — median of multiple rounds, same session and same
loops for every lib. The fsync row has a single bar because only `all_box`
offers that guarantee (`writeAndFlush()`).

`all_box` intentionally doesn't try to be a database or resolve its own
`path` — that's a design choice, not a gap.
[Full, detailed comparison, including a performance benchmark, here](documentation/en/comparison.md).

## 🤔 When to use it (and when not to)

Reach for `all_box` when you want simple key-value storage — settings,
flags, small app state — with synchronous reads after boot, optimistic
writes with an explicit opt-in to durable confirmation, and a reactive
layer with no external state-management dependency.

Reach for something else when you specifically need what it specializes
in: Web support and custom type adapters (Hive), a full embedded database
with queries/indexes/relations (Isar), or the Flutter ecosystem's most
"standard" platform wrapper (SharedPreferences) for a small app that
doesn't need built-in reactivity.

## 🧪 Testing

```bash
flutter test
```

The tests specifically cover the bug scenarios mapped above: a file
corrupted with random binary bytes, invalid JSON, fallback to `.bak`,
multiple `write()` calls coalescing into a single flush, isolation between
containers, correct listener notification on `erase()`, and
`listenKey`/`listenAll` being correctly removed.

### Testing code that consumes `all_box`

If you're testing your own app/package (not `all_box` itself), you don't
need a real directory on disk — use the in-memory backend:

```dart
await AllBox.initWithMemoryBackendForTesting(
  'my_container',
  initialValues: {'darkMode': true},
);
```

This does no real I/O and schedules no real `Timer` (every `write()`
"flushes" synchronously) — this matters especially inside `testWidgets`:
your `FakeAsync` zone expects every `Timer` to resolve before the test
ends, and a real disk-backed container would leave a debounce `Timer`
pending there.

## 📚 Documentation

- [Comparison](documentation/en/comparison.md) — detailed comparison vs. GetStorage, Hive, Isar, SharedPreferences, including a performance benchmark.

## 📦 Other packages by us

`all_box` is part of a small family of zero/low-dependency Dart & Flutter
packages published under the
[`opensource.tatamemaster.com.br`](https://pub.dev/publishers/opensource.tatamemaster.com.br/packages)
verified publisher:

| Package | Version | Description |
|---|---|---|
| [`all_observer`](https://pub.dev/packages/all_observer) | [![pub](https://img.shields.io/pub/v/all_observer.svg)](https://pub.dev/packages/all_observer) | Reactive state for Flutter with zero dependencies — `final count = 0.obs;` + `Observer(...)`. |
| [`all_validations_br`](https://pub.dev/packages/all_validations_br) | [![pub](https://img.shields.io/pub/v/all_validations_br.svg)](https://pub.dev/packages/all_validations_br) | Brazilian document validation (CPF, CNPJ, CNH, PIX), input formatters/masks, JWT/UUID/currency/encryption utilities. |
| [`all_image_compress`](https://pub.dev/packages/all_image_compress) | [![pub](https://img.shields.io/pub/v/all_image_compress.svg)](https://pub.dev/packages/all_image_compress) | Pure-Dart image compression (JPEG, PNG, GIF, BMP, TIFF, WebP), running in isolates. |

## 👥 Contributors

[![Contributors](https://contrib.rocks/image?repo=CriandoGames/all_box)](https://github.com/CriandoGames/all_box/graphs/contributors)

Made with [contrib.rocks](https://contrib.rocks).

Contributions are welcome! Read [CONTRIBUTING.md](CONTRIBUTING.md) to get
started.

---

Issues and pull requests are welcome at the
[GitHub repository](https://github.com/CriandoGames/all_box). Distributed under the [MIT](LICENSE) license.
