import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

// `hide VoidCallback`: the core also defines its own `VoidCallback` typedef
// (identical `void Function()` signature) so it has zero Flutter imports.
// Both would otherwise be visible here under the same name, which is an
// ambiguous import; Flutter's own `VoidCallback` (from foundation.dart) is
// used throughout this file instead.
import '../core/all_box_impl.dart' hide VoidCallback;

/// A [ValueListenable] backed by a single key of an [AllBox] container.
///
/// This is the reactive building block used by [AllBoxBuilder]. It is a
/// plain `ChangeNotifier`/`ValueListenable` — pure Flutter, no external
/// state-management dependency anywhere in this class.
///
/// **PT-BR:** Um [ValueListenable] baseado em uma única chave de um
/// container [AllBox].
///
/// Este é o bloco reativo usado por [AllBoxBuilder]. É um
/// `ChangeNotifier`/`ValueListenable` puro — Flutter puro, sem nenhuma
/// dependência externa de gerenciamento de estado nesta classe.
class AllBoxListenable<T> extends ChangeNotifier
    implements ValueListenable<T?> {
  /// Creates a listenable for [key] inside [box] (defaults to the default
  /// container). [box] must already be initialized.
  ///
  /// **PT-BR:** Cria um listenable para [key] dentro de [box] (usa o
  /// container padrão se omitido). [box] já deve estar inicializado.
  AllBoxListenable(
    this.key, {
    AllBox? box,
  }) : box = box ?? AllBox() {
    _value = this.box.read<T>(key);
    _callback = () {
      final newValue = this.box.read<T>(key);
      if (newValue != _value) {
        _value = newValue;
        notifyListeners();
      }
    };
    this.box.listenKey(key, _callback);
  }

  /// The key this listenable tracks.
  ///
  /// **PT-BR:** A chave que este listenable acompanha.
  final String key;

  /// The container this listenable reads from.
  ///
  /// **PT-BR:** O container do qual este listenable lê.
  final AllBox box;

  late T? _value;
  late final VoidCallback _callback;
  bool _disposed = false;

  @override
  T? get value => _value;

  /// Writes [newValue] back to [box] under [key]. Since [AllBox.write] is
  /// synchronous/optimistic and notifies listeners immediately, this updates
  /// [value] (and any listening [AllBoxBuilder]) right away.
  ///
  /// **PT-BR:** Escreve [newValue] de volta em [box] sob [key]. Como
  /// [AllBox.write] é síncrono/otimista e notifica os listeners
  /// imediatamente, isso atualiza [value] (e qualquer [AllBoxBuilder] que
  /// esteja ouvindo) na hora.
  set value(T? newValue) {
    box.write(key, newValue);
  }

  @override
  void dispose() {
    if (!_disposed) {
      _disposed = true;
      box.removeListenKey(key, _callback);
    }
    super.dispose();
  }
}

/// A widget that rebuilds whenever [keyName] changes inside [box].
///
/// Implemented purely with Flutter's own `ValueListenableBuilder` — no
/// external state-management dependency.
///
/// ```dart
/// AllBoxBuilder<bool>(
///   keyName: 'darkMode',
///   builder: (context, isDark) => Switch(
///     value: isDark ?? false,
///     onChanged: (v) => AllBox().write('darkMode', v),
///   ),
/// )
/// ```
///
/// **PT-BR:** Um widget que reconstrói sempre que [keyName] muda dentro de
/// [box].
///
/// Implementado puramente com o `ValueListenableBuilder` do próprio
/// Flutter — sem nenhuma dependência externa de gerenciamento de estado.
///
/// ```dart
/// AllBoxBuilder<bool>(
///   keyName: 'darkMode',
///   builder: (context, isDark) => Switch(
///     value: isDark ?? false,
///     onChanged: (v) => AllBox().write('darkMode', v),
///   ),
/// )
/// ```
class AllBoxBuilder<T> extends StatefulWidget {
  const AllBoxBuilder({
    super.key,
    required this.keyName,
    required this.builder,
    this.box,
  });

  /// The storage key to watch.
  ///
  /// **PT-BR:** A chave de armazenamento a ser observada.
  final String keyName;

  /// The container to read from. Defaults to the default container.
  ///
  /// **PT-BR:** O container de onde ler. Usa o container padrão se
  /// omitido.
  final AllBox? box;

  /// Called with the current value every time it changes.
  ///
  /// **PT-BR:** Chamado com o valor atual toda vez que ele muda.
  final Widget Function(BuildContext context, T? value) builder;

  @override
  State<AllBoxBuilder<T>> createState() => _AllBoxBuilderState<T>();
}

class _AllBoxBuilderState<T> extends State<AllBoxBuilder<T>> {
  late AllBoxListenable<T> _listenable;

  @override
  void initState() {
    super.initState();
    _listenable = AllBoxListenable<T>(widget.keyName, box: widget.box);
  }

  @override
  void didUpdateWidget(covariant AllBoxBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyName != widget.keyName || oldWidget.box != widget.box) {
      _listenable.dispose();
      _listenable = AllBoxListenable<T>(widget.keyName, box: widget.box);
    }
  }

  @override
  void dispose() {
    _listenable.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<T?>(
      valueListenable: _listenable,
      builder: (context, value, _) => widget.builder(context, value),
    );
  }
}
