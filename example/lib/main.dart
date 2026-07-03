import 'package:all_box/all_box.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

/// This is the example app's job, not AllBox's: AllBox never resolves its
/// own storage directory (see spec item 9 / README "Erros de path/plugin
/// evitados"). Here we do it explicitly, *after*
/// `WidgetsFlutterBinding.ensureInitialized()`, which is exactly the point
/// where resolving platform channels (path_provider) too early — before the
/// binding is ready, or inside a customized Activity (e.g.
/// `FlutterFragmentActivity`) — tends to throw `MissingPluginException`.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final directory = await getApplicationDocumentsDirectory();
  await AllBox.init('example_box', path: directory.path);

  runApp(const AllBoxExampleApp());
}

class AllBoxExampleApp extends StatelessWidget {
  const AllBoxExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AllBox example',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const CounterPage(),
    );
  }
}

/// Demonstrates the whole public surface used day to day:
///  - `AllBox()` factory (singleton per container name)
///  - `write()` (optimistic + debounced) vs `writeAndFlush()`
///  - `AllBoxBuilder<T>` for a reactive widget with no `Obx`/`get`
///  - `listenAll` for a global side-effect (a SnackBar) outside the widget
///    that owns the value
///  - `flushNow()` from `AppLifecycleState.paused`, so nothing pending is
///    lost if the OS kills the process in the background.
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> with WidgetsBindingObserver {
  final AllBox _box = AllBox('example_box');
  VoidCallback? _disposeGlobalListener;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _disposeGlobalListener = _box.listenAll(() {
      debugPrint('all_box: container "example_box" changed');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      // Force whatever is still debounced to hit disk before a possible
      // process kill in the background.
      _box.flushNow();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeGlobalListener?.call();
    super.dispose();
  }

  void _increment() {
    final current = _box.readOrDefault<int>('counter', 0);
    // Fire-and-forget: memory + listeners update synchronously; disk
    // catches up ~100ms later, debounced.
    _box.write('counter', current + 1);
  }

  Future<void> _incrementAndWaitForDisk() async {
    final current = _box.readOrDefault<int>('counter', 0);
    await _box.writeAndFlush('counter', current + 1);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Persisted to disk.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('all_box example')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Value of "counter" (reactive, no Obx/get):'),
            const SizedBox(height: 8),
            AllBoxBuilder<int>(
              keyName: 'counter',
              box: _box,
              builder: (context, value) => Text(
                '${value ?? 0}',
                style: Theme.of(context).textTheme.displayMedium,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton(
                  onPressed: _increment,
                  child: const Text('write() (optimistic)'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: _incrementAndWaitForDisk,
                  child: const Text('writeAndFlush()'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _box.erase,
                  child: const Text('erase()'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
