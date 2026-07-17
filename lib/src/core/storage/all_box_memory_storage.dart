import 'all_box_storage.dart';

/// Pure in-memory [AllBoxStorage]: no real disk I/O, no browser storage, no
/// [Timer]. `save` mutates an in-memory snapshot directly and completes
/// without ever suspending — there is no `await` in its body — so a caller
/// that fires it without awaiting still sees the mutation applied
/// synchronously by the time the call returns (Dart runs an `async`
/// function's body eagerly, synchronously, up to its first `await`; with
/// none present, the whole body runs before control returns to the caller).
///
/// This is what backs `AllBox.memory()`, used for testing app/package code
/// that consumes `all_box` without any real filesystem or browser access.
///
/// **PT-BR:** [AllBoxStorage] puramente em memória: sem I/O real em disco,
/// sem storage de navegador, sem [Timer]. `save` muda um snapshot em
/// memória diretamente e completa sem nunca suspender — não há `await` no
/// seu corpo — então quem chama sem aguardar ainda vê a mutação aplicada de
/// forma síncrona no momento em que a chamada retorna (o Dart executa o
/// corpo de uma função `async` de forma antecipada e síncrona até o
/// primeiro `await`; sem nenhum, o corpo inteiro roda antes de devolver o
/// controle para quem chamou).
///
/// É isso que sustenta o `AllBox.memory()`, usado para testar código de
/// apps/pacotes que consomem o `all_box` sem acesso real a sistema de
/// arquivos ou navegador.
class AllBoxMemoryStorage implements AllBoxStorage {
  Map<String, dynamic> _snapshot = <String, dynamic>{};
  bool _everPersisted = false;

  @override
  Future<bool> hasPersistedData() async => _everPersisted;

  @override
  Future<Map<String, dynamic>> load() async =>
      Map<String, dynamic>.of(_snapshot);

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    _snapshot = Map<String, dynamic>.of(snapshot);
    _everPersisted = true;
  }

  @override
  Future<void> delete() async {
    _snapshot = <String, dynamic>{};
  }

  @override
  Future<void> close() async {}
}
