import 'package:all_box/all_box.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'benchmark/benchmark_page.dart';

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
///  - `erase()`
///  - `flushNow()` from `AppLifecycleState.paused`, so nothing pending is
///    lost if the OS kills the process in the background.
///
/// `all_box` has no reactive/listener API — the UI updates by calling
/// `setState` right after each `write()`/`writeAndFlush()`/`erase()` call,
/// same as you would with any other synchronous, non-reactive storage.
class CounterPage extends StatefulWidget {
  const CounterPage({super.key});

  @override
  State<CounterPage> createState() => _CounterPageState();
}

class _CounterPageState extends State<CounterPage> with WidgetsBindingObserver {
  final AllBox _box = AllBox('example_box');
  late int _counter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _counter = _box.readOrDefault<int>('counter', 0);
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
    super.dispose();
  }

  void _increment() {
    final next = _counter + 1;
    // Fire-and-forget: memory updates synchronously; disk catches up ~100ms
    // later, debounced.
    _box.write('counter', next);
    setState(() => _counter = next);
  }

  Future<void> _incrementAndWaitForDisk() async {
    final next = _counter + 1;
    await _box.writeAndFlush('counter', next);
    if (mounted) {
      setState(() => _counter = next);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Persisted to disk.')),
      );
    }
  }

  void _erase() {
    _box.erase();
    setState(() => _counter = 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('all_box example'),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed),
            tooltip: 'Comparativo de storage',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const BenchmarkPage(),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Value of "counter":'),
            const SizedBox(height: 8),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.displayMedium,
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
                  onPressed: _erase,
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
