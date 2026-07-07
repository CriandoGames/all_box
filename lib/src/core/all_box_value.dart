import 'all_box_impl.dart';

/// A small persistent value handle returned by the `.val()` extension.
///
/// Not a state-management framework by itself — just a thin, dependency-free
/// wrapper around a single [AllBox] key, with zero coupling to any
/// dependency-injection mechanism.
///
/// **PT-BR:** Um pequeno handle de valor persistente retornado pela
/// extensão `.val()`.
///
/// Não é um framework de gerenciamento de estado por si só — apenas um
/// wrapper fino e sem dependências em torno de uma única chave do [AllBox],
/// sem nenhum acoplamento a mecanismos de injeção de dependência.
class AllBoxValue<T> {
  AllBoxValue(this.key, this.box, this._defaultValue);

  /// The storage key this value reads/writes.
  ///
  /// **PT-BR:** A chave de armazenamento que este valor lê/escreve.
  final String key;

  /// The container backing this value.
  ///
  /// **PT-BR:** O container que sustenta este valor.
  final AllBox box;

  final T _defaultValue;

  /// The current value, or the default supplied to `.val()` if absent.
  ///
  /// **PT-BR:** O valor atual, ou o padrão fornecido a `.val()` se ausente.
  T get value => box.readOrDefault<T>(key, _defaultValue);

  /// Writes a new value back to [box] (optimistic + debounced, like any
  /// other [AllBox.write]).
  ///
  /// **PT-BR:** Escreve um novo valor de volta em [box] (otimista +
  /// debounced, como qualquer outro [AllBox.write]).
  set value(T newValue) => box.write(key, newValue);

  /// Shorthand for [value], so an [AllBoxValue] can be used as `myValue()`.
  ///
  /// **PT-BR:** Atalho para [value], para que um [AllBoxValue] possa ser
  /// usado como `myValue()`.
  T call() => value;

  @override
  String toString() => 'AllBoxValue<$T>($key: $value)';
}

/// Adds a `.val()` helper on [String], turning any string literal into a
/// tiny persistent, reactive-free value handle:
///
/// ```dart
/// final darkMode = 'darkMode'.val(false);
/// print(darkMode.value);   // read
/// darkMode.value = true;   // write (optimistic + debounced)
/// ```
///
/// This extension has no dependency-injection coupling of any kind — it is
/// purely a convenience wrapper around [AllBox.read]/[AllBox.write].
///
/// **PT-BR:** Adiciona um helper `.val()` em [String], transformando
/// qualquer string literal em um pequeno handle de valor persistente (sem
/// reatividade):
///
/// ```dart
/// final darkMode = 'darkMode'.val(false);
/// print(darkMode.value);   // leitura
/// darkMode.value = true;   // escrita (otimista + debounced)
/// ```
///
/// Esta extensão não tem nenhum acoplamento a injeção de dependência — é
/// puramente um wrapper de conveniência em torno de
/// [AllBox.read]/[AllBox.write].
extension AllBoxValueExtension on String {
  AllBoxValue<T> val<T>(T defaultValue, {AllBox? box}) {
    return AllBoxValue<T>(this, box ?? AllBox(), defaultValue);
  }
}
