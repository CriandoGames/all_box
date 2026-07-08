// Benchmark comparison screen. Runs the scenarios from
// `storage_benchmark.dart` against every adapter, sequentially, and shows
// the results as relative bars (shorter = faster) per scenario, with a
// one-tap "copy as Markdown" for the README.
//
// **PT-BR:** Tela de comparativo. Roda os cenários do
// `storage_benchmark.dart` contra cada adapter, em sequência, e mostra os
// resultados como barras relativas (menor = mais rápido) por cenário, com
// um "copiar como Markdown" de um toque para o README.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'storage_benchmark.dart';

class BenchmarkPage extends StatefulWidget {
  const BenchmarkPage({super.key});

  @override
  State<BenchmarkPage> createState() => _BenchmarkPageState();
}

class _BenchmarkPageState extends State<BenchmarkPage> {
  List<LibResult>? _results;
  String? _progress;
  bool _running = false;

  String get _environment {
    final mode = kReleaseMode
        ? 'release'
        : kProfileMode
            ? 'profile'
            : 'debug';
    return '${Platform.operatingSystem} ${Platform.operatingSystemVersion} '
        '— modo $mode — mediana de $kMemoryRounds rodadas '
        '(memória) / $kDurableRounds (disco)';
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _results = null;
      _progress = 'Preparando…';
    });

    try {
      final docs = await getApplicationDocumentsDirectory();
      final basePath = '${docs.path}/all_box_bench';

      final adapters = <StorageAdapter>[
        AllBoxAdapter(),
        HiveAdapter(),
        SharedPreferencesAdapter(),
      ];

      final results = <LibResult>[];
      for (final adapter in adapters) {
        results.add(
          await runBenchmark(
            adapter,
            basePath,
            onProgress: (message) {
              if (mounted) setState(() => _progress = message);
            },
          ),
        );
      }

      if (mounted) {
        setState(() {
          _results = results;
          _progress = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _progress = 'Falhou: $error');
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _copyMarkdown() async {
    final results = _results;
    if (results == null) return;
    await Clipboard.setData(
      ClipboardData(text: resultsAsMarkdown(results, _environment)),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tabela Markdown copiada.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comparativo de storage'),
        actions: [
          if (results != null)
            IconButton(
              icon: const Icon(Icons.copy_all),
              tooltip: 'Copiar como Markdown',
              onPressed: _copyMarkdown,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (kDebugMode)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  '⚠️ Você está em modo DEBUG. Os números ficam inflados '
                  '(o all_box, em particular, paga um guard extra de '
                  'jsonEncode por write que não existe em release). Para '
                  'números publicáveis: flutter run --profile',
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _running ? null : _run,
            icon: const Icon(Icons.speed),
            label: Text(_running ? 'Rodando…' : 'Rodar benchmark'),
          ),
          if (_progress != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(_progress!)),
              ],
            ),
          ],
          if (results != null) ...[
            const SizedBox(height: 8),
            Text(_environment, style: Theme.of(context).textTheme.bodySmall),
            for (final scenario in Scenario.values)
              _ScenarioCard(scenario: scenario, results: results),
            const SizedBox(height: 8),
            Text(
              'Justiça na comparação: em "escrita confirmada", cada lib '
              'responde com o próprio contrato de "persistido" — nenhuma '
              'faz fsync aí (all_box usa writeAndSave, Hive anexa no log, '
              'SharedPreferences cruza o platform channel). A linha de '
              'fsync mostra só o all_box porque nenhuma das outras oferece '
              'garantia contra queda de energia.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _ScenarioCard extends StatelessWidget {
  const _ScenarioCard({required this.scenario, required this.results});

  final Scenario scenario;
  final List<LibResult> results;

  @override
  Widget build(BuildContext context) {
    final entries = <({String lib, ScenarioResult result})>[
      for (final lib in results)
        if (lib[scenario] != null) (lib: lib.libName, result: lib[scenario]!),
    ]..sort(
        (a, b) => a.result.elapsed.compareTo(b.result.elapsed),
      );
    if (entries.isEmpty) return const SizedBox.shrink();

    final slowest = entries.last.result.elapsed.inMicroseconds;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${scenario.label} — ${scenario.ops} ops (menor = melhor)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final entry in entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(width: 140, child: Text(entry.lib)),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final fraction = slowest == 0
                              ? 0.0
                              : entry.result.elapsed.inMicroseconds / slowest;
                          return Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: constraints.maxWidth *
                                  fraction.clamp(0.02, 1.0),
                              height: 14,
                              decoration: BoxDecoration(
                                color: entry.lib == 'all_box'
                                    ? Theme.of(context).colorScheme.primary
                                    : Theme.of(context)
                                        .colorScheme
                                        .secondaryContainer,
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 110,
                      child: Text(
                        '${entry.result.elapsed.inMilliseconds}ms '
                        '(${entry.result.perOpMicros.toStringAsFixed(1)}µs/op)',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
