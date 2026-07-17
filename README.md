<h1 align="center">all_box</h1>

<p align="center">
🇧🇷 <a href="https://github.com/CriandoGames/all_box/blob/main/README.pt-BR.md">Português</a> | 🇺🇸 English
</p>

<p align="center">
  <a href="https://pub.dev/packages/all_box"><img src="https://img.shields.io/pub/v/all_box.svg?label=pub.dev" alt="pub version"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/likes/all_box?label=likes" alt="pub likes"></a>
  <a href="https://pub.dev/packages/all_box/score"><img src="https://img.shields.io/pub/points/all_box?label=pub%20points" alt="pub points"></a>
  <a href="https://github.com/CriandoGames/all_box/blob/main/LICENSE"><img src="https://img.shields.io/github/license/CriandoGames/all_box" alt="license"></a>
  <img src="https://img.shields.io/badge/tests-114-brightgreen" alt="114 tests">
</p>

<p align="center">
💡 Simple, synchronous key-value storage for Dart and Flutter, with a crash-safe write strategy.
</p>

## Table of contents

- [Features](#-features)
- [Installing](#-installing)
- [Example App](#-example-app)
- [Usage examples](#-usage-examples)
- [Need reactivity?](#-need-reactivity)
- [Separating data by user or context](#-separating-data-by-user-or-context)
- [API](#-api)
- [How it works](#️-how-it-works)
- [Comparison](#-comparison)
- [When to use it (and when not to)](#-when-to-use-it-and-when-not-to)
- [Testing](#-testing)
- [Documentation](#-documentation)
- [Other packages by us](#-other-packages-by-us)

## 🚀 Features

- 🪶 **Synchronous reads.** After `init()`, every `read<T>()` is
  synchronous — no `Future`, no `FutureBuilder`.
- 🧱 **Pure Dart, zero Flutter dependency.** Works in any Dart environment
  — CLI, server, or Flutter app.
- 🛡️ **Crash-safe write strategy.** Designed to avoid partially-written
  files on IO platforms. See [How it works](#️-how-it-works).
- 📍 **Explicit `path`, never resolved internally.** You decide where the
  container lives — no internal `path_provider` dependency, so no
  plugin/Activity resolution surprises.
- ⚡ **Optimistic, debounced writes**, with opt-in stronger durability
  tiers (`writeAndSave()`, `writeAndFlush()`) when you need them.
- 🧭 **Observable persistence failures.** Keep `write()` synchronous, but
  opt into `onPersistenceError` when you need to log/report failed async
  persistence.
- 🧹 **Explicit lifecycle APIs.** Use `close()` to release a container and
  `destroy()` to remove its persisted data.
- 🧪 **In-memory storage for testing.** `AllBox.memory()` — no real I/O,
  no real `Timer`.
- 🌐 **Web support**, backed by `window.localStorage`.
- 🔌 **No built-in reactivity.** Bring your own — see
  [Need reactivity?](#-need-reactivity).

Part of the `all_*` family of open-source packages alongside
[`all_validations_br`](https://pub.dev/packages/all_validations_br)
(Brazilian validations, utilities and encryption) and `all_image_compress`
(image compression).

## 📦 Installing

```
dart pub add all_box
```

```yaml
dependencies:
  all_box: ^0.7.0
```

`all_box` is pure Dart and has a single entrypoint:

```dart
import 'package:all_box/all_box.dart';

// Web: no `path` needed — AllBox automatically uses window.localStorage.
final box = await AllBox.init('settings');

// IO (native VM/AOT, incl. Flutter mobile/desktop): pass a directory.
final box = await AllBox.init('settings', path: dir.path);

box.write('name', 'Carlos');
final name = box.read<String>('name');
```

Testing your own app/package against a real `AllBox` instance, with no real
I/O at all:

```dart
final box = await AllBox.memory('settings', initialData: {'darkMode': true});
```

## 📱 Example App

The `example/` directory contains an interactive Flutter app (`CounterPage`)
demonstrating the day-to-day public surface: optimistic `write()` vs.
`writeAndFlush()`, `erase()`, and `flushNow()` fired on
`AppLifecycleState.paused`.

```bash
cd example
flutter pub get
flutter run
```

## 🧪 Usage examples

### Initialization

```dart
import 'package:all_box/all_box.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  await AllBox.init('my_container', path: dir.path);

  runApp(const MyApp());
}
```

`path` is required on IO platforms and ignored on Web (`AllBox` never
resolves it for you). There's also an advanced `storage:` argument to plug
in your own `AllBoxStorage` implementation, but everyday code never needs
it.

Container names remain permissive by default for compatibility. If you want
IO container names to be checked before any file access, opt in:

```dart
await AllBox.init(
  'settings',
  path: dir.path,
  validateContainerName: true,
);
```

Strict validation accepts only letters, numbers, `.`, `_` and `-`, and
rejects path-like or OS-reserved names such as `../data`, `a/b`,
`cache:name`, `CON` and `NUL`.

### Seeding data on first run

```dart
await AllBox.init(
  'settings',
  path: dir.path,
  initialData: const {'darkMode': false, 'onboarded': false},
);
```

`initialData` only applies the first time a container is created — see
[How it works](#️-how-it-works) for the exact rule.

### Reading and writing

```dart
final box = AllBox('my_container');

box.write('name', 'Carlos');               // optimistic + debounced
String? name = box.read<String>('name');
String safeName = box.readOrDefault<String>('name', 'anonymous');

await box.writeAndSave('name', 'Carlos');  // waits for the OS write
await box.writeAndFlush('name', 'Carlos'); // waits for disk confirmation

box.remove('name');
box.erase(); // clears everything

await box.flushNow(); // forces a flush now, e.g. on AppLifecycleState.paused
```

### Persistence errors

`write()` intentionally stays synchronous: it updates memory and schedules a
debounced flush. If that later persistence step fails, you can observe it
without turning `all_box` into a reactive state library:

```dart
final box = await AllBox.init(
  'settings',
  path: dir.path,
  onPersistenceError: (AllBoxPersistenceError error) {
    // log/report error.container, error.operation, error.cause
  },
);

box.write('theme', 'dark');
```

`writeAndSave()`, `writeAndFlush()` and `flushNow()` still complete with an
error when their awaited persistence fails. The same failure is also reported
through `onPersistenceError`.

### Releasing or destroying a container

```dart
await box.close(); // flushes pending data, closes storage, unregisters it

await box.close(flushPending: false); // discards pending debounced writes

await box.destroy(); // deletes persisted data, closes storage, unregisters it
```

`destroy()` is a logical deletion API. It removes AllBox's `.db`, `.tmp` and
`.bak` files on IO, or the Web storage key on Web, but it is not a secure
wipe and does not claim to overwrite physical storage.

### Value with a safe fallback

```dart
final box = AllBox('settings');
final theme = box.readOrDefault<String>('theme', 'light');
// Returns 'light' if the 'theme' key doesn't exist yet
```

### Updating a widget after a write

`all_box` has no built-in reactivity, so a widget that displays a stored
value re-reads it and calls `setState` right after writing:

```dart
class DarkModeSwitch extends StatefulWidget {
  const DarkModeSwitch({super.key});

  @override
  State<DarkModeSwitch> createState() => _DarkModeSwitchState();
}

class _DarkModeSwitchState extends State<DarkModeSwitch> {
  late bool _darkMode = AllBox().readOrDefault<bool>('darkMode', false);

  void _toggle(bool value) {
    AllBox().write('darkMode', value);
    setState(() => _darkMode = value);
  }

  @override
  Widget build(BuildContext context) {
    return Switch(value: _darkMode, onChanged: _toggle);
  }
}
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

## 🔌 Need reactivity?

`all_box` intentionally does not ship a reactive layer. It stays focused
on storage. If you want reactive state for Flutter, use
[`all_observer`](https://pub.dev/packages/all_observer) with
`Observer(...)` and keep storage and UI state separated — or wire `all_box`
into a `ChangeNotifier`/state-management solution you already use.

## 🧩 Separating data by user or context

`all_box` doesn't ship a dedicated "scope", "namespace" or "collection" API
— that's on purpose, to keep the surface small. In real apps you still need
to separate local data by who it belongs to: the logged-in user, an
account, a gym, a company, a session, or just app-wide state. Two patterns
cover this well with the API that already exists.

**A different container per context.** `AllBox.init(container, ...)` takes
an arbitrary container name, and each name is a fully isolated storage —
its own file on IO, its own `localStorage` key on Web:

```dart
final appBox = await AllBox.init('app_settings', path: dir.path);
final userBox = await AllBox.init('user_$userId', path: dir.path);
```

Erasing or clearing one container never touches the other. This fits well
when the number of contexts is small and known ahead of time — e.g. one
container per logged-in user, plus one for app-wide settings.

**Key prefixes inside a single container.** When contexts are more
dynamic, or you'd rather keep everything in one place, prefixing keys works
just as well:

```dart
final userId = 'user_123';

box.write('user:$userId:theme', 'dark');
box.write('user:$userId:profile', profile);

final theme = box.read<String>('user:$userId:theme');
```

```dart
box.write('app:last_logged_user', userId);
box.write('app:language', 'pt-BR');

final language = box.read<String>('app:language');
```

A good practice is to separate keys by context. This helps avoid data
conflicts and makes it easier to remove information from a specific user
without deleting global app settings.

This separation is useful for:

- apps with multiple logged-in users on the same device;
- multi-tenant/SaaS apps (company, gym, organization);
- caching API responses per account;
- local preferences per user profile;
- safely wiping a user's data on logout, without touching global settings;
- keeping temporary session data apart from persistent app state.

For larger projects, consider centralizing key names in a dedicated class
to avoid scattered strings across the app:

```dart
class StorageKeys {
  static String userTheme(String userId) => 'user:$userId:theme';
  static String userProfile(String userId) => 'user:$userId:profile';

  static const appLanguage = 'app:language';
  static const lastLoggedUser = 'app:last_logged_user';
}
```

Either pattern keeps `all_box` doing what it's meant for — preferences,
local settings, small app state and micro caches — not a replacement for a
full embedded database with queries, indexes or relations (see
[When to use it](#-when-to-use-it-and-when-not-to)).

## 📚 API

| Member | Description |
| --- | --- |
| `AllBox([container])` | Factory constructor; returns a singleton per container name. |
| `static AllBox.init(container, {path, flushDelay, initialData, storage, onPersistenceError, validateContainerName})` | Loads `container` into memory and returns the initialized `AllBox`. `path` is required on IO platforms, ignored on Web. Container-name validation is opt-in for compatibility. |
| `static AllBox.memory(container, {initialData})` | Recommended way to test code that consumes `all_box`: no real I/O, no real `Timer`. Replaces the deprecated `initWithMemoryBackendForTesting`. |
| `T? read<T>(key)` / `T readOrDefault<T>(key, fallback)` | Synchronous reads. |
| `void write(key, value)` | Optimistic, debounced write. |
| `Future<void> writeAndSave(key, value)` | Writes and waits for the OS write to complete. |
| `Future<void> writeAndFlush(key, value)` | Writes and waits for the strongest durability guarantee available. |
| `void remove(key)` / `void erase()` | Removes a key / clears everything. |
| `Future<void> flushNow()` | Forces an immediate flush, bypassing the debounce window. |
| `Future<void> close({flushPending})` | Flushes or discards pending writes, closes the backend storage and removes the container from the internal registry. |
| `Future<void> destroy()` | Deletes persisted data for the container, closes storage and removes the container from the registry. Not a secure wipe. |
| `hasData(key)`, `getKeys()`, `getValues()` | Introspection. |

## 🛠️ How it works

`all_box` keeps a short list of deliberate design choices:

- **`path` is always explicit on IO, automatic on Web.** No internal
  directory resolution, no plugin dependency.
- **`initialData` only ever applies on a genuine first run.**
- **`init()` is deterministic under concurrency.** Equivalent concurrent
  calls share one initialization; conflicting options are rejected.
- **Container-name validation is opt-in.** Existing apps keep their current
  names by default; strict mode is available through `validateContainerName`.
- **Persistence failures are observable.** `onPersistenceError` reports
  async debounced failures without changing `write()` into an async API.
- **Web is currently Window/localStorage only.** Web Workers, Service
  Workers, safe multi-tab writes, and IndexedDB are future backend work, not
  promises of the current localStorage backend.
- **No built-in reactivity** — see [Need reactivity?](#-need-reactivity).

The write-ahead + atomic-rename pipeline, flush/debounce coordination, the
`dart:js_interop` Web backend, and the full list of known limitations
(Web storage limits, isolate-safety, `File.rename` portability) are
documented in [Internal architecture](documentation/en/architecture.md).

## ⚖️ Comparison

| | `all_box` | GetStorage | Hive | Isar | SharedPreferences |
|---|---|---|---|---|---|
| Reads | Synchronous, in memory | Synchronous, in memory | Synchronous (open box) | Synchronous (simple) / async (queries) | Async |
| Storage `path` | Explicit, required | Resolved internally | Resolved by caller | Resolved by caller | Resolved by platform |
| Crash-safety strategy | Write-ahead + atomic rename + `.bak`, documented | Not documented at the same level | Internal WAL/compaction | WAL via its own engine | Platform-dependent |
| Web support | Yes (`localStorage`) | Yes | Yes | Yes | Yes |
| Reactivity | None (bring your own) | `GetBuilder`/`Obx` (GetX) | `ValueListenableBuilder` over `box.listenable()` | `watchObject`/`watchLazy` (streams) | None — needs your own wrapper |
| Scope | Key-value storage only | Storage + some UI utils (GetX) | Box-oriented storage | Full database | Platform wrapper |

![Performance comparison: all_box vs. Hive and SharedPreferences, measured on-device in profile mode](doc/comparison_benchmark_en.png)

Measured on-device (Android, profile mode) via the example app's "Storage
comparison" screen. Full methodology, numbers, and per-library caveats in
[Comparison](documentation/en/comparison.md).

`all_box` intentionally doesn't try to be a database or resolve its own
`path` — that's a design choice, not a gap.

## 🤔 When to use it (and when not to)

Reach for `all_box` when you want simple key-value storage — settings,
flags, small app state — with synchronous reads after boot and optimistic
writes with an explicit opt-in to durable confirmation. Bring your own
reactivity (see [above](#-need-reactivity)) if you need it.

Reach for something else when you specifically need what it specializes
in: custom type adapters for complex objects (Hive), a full embedded
database with queries/indexes/relations (Isar), the Flutter ecosystem's
most "standard" platform wrapper (SharedPreferences), or a storage library
with built-in reactivity.

## 🧪 Testing

```bash
flutter test
```

If you're testing your own app/package (not `all_box` itself), use
in-memory storage instead of a real directory or browser:

```dart
final box = await AllBox.memory(
  'my_container',
  initialData: {'darkMode': true},
);
```

This does no real I/O and schedules no real `Timer`, which matters
specifically inside `testWidgets` (its `FakeAsync` zone expects every
`Timer` to resolve before the test ends).

(The older `AllBox.initWithMemoryBackendForTesting()` still works — it's
now a thin, `@Deprecated` wrapper around `AllBox.memory()`.)

## 📚 Documentation

- [Comparison](documentation/en/comparison.md) — detailed comparison vs. GetStorage, Hive, Isar, SharedPreferences, including a performance benchmark.
- [Internal architecture](documentation/en/architecture.md) — write-ahead + atomic rename pipeline, flush coordination, the `dart:js_interop` Web backend, and known limitations.

## 📦 Other packages by us

`all_box` is part of a small family of Dart & Flutter packages published
under the
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
