/// AllBox's optional Flutter reactive layer: `AllBoxListenable` and
/// `AllBoxBuilder`, built directly on `ChangeNotifier` and
/// `ValueListenable` — no external state-management dependency.
///
/// This re-exports everything from `package:all_box/all_box.dart`, so
/// Flutter apps only need this single import.
///
/// Dart-only consumers (no Flutter) should import
/// `package:all_box/all_box.dart` instead.
///
/// **PT-BR:** Camada reativa opcional do AllBox para Flutter:
/// `AllBoxListenable` e `AllBoxBuilder`, construídos diretamente sobre
/// `ChangeNotifier` e `ValueListenable` — sem nenhuma dependência externa
/// de gerenciamento de estado.
///
/// Isto reexporta tudo de `package:all_box/all_box.dart`, então apps
/// Flutter só precisam deste único import.
///
/// Consumidores só-Dart (sem Flutter) devem importar
/// `package:all_box/all_box.dart`.
library all_box_flutter;

export 'all_box.dart';
export 'src/flutter/all_box_listenable.dart'
    show AllBoxListenable, AllBoxBuilder;
