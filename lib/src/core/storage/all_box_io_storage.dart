import 'dart:convert';
import 'dart:io';

import 'all_box_storage.dart';
import 'all_box_storage_exception.dart';

/// Disk-backed [AllBoxStorage]: one container maps to one `<container>.db`
/// file (plus `.tmp`/`.bak` companions) inside a given directory.
///
/// Reuses, unchanged, the crash-safe pipeline `all_box` has always used:
/// write-ahead to a `.tmp` file, best-effort backup of the previous `.db`
/// into `.bak` (a metadata-only rename, not a byte copy), then an atomic
/// rename of `.tmp` over `.db`. Reads try `.db` first, fall back to `.bak`,
/// and never throw — any corruption (missing file, invalid UTF-8, invalid
/// JSON) simply results in an empty map.
///
/// Debouncing, coalescing and the flush queue are *not* this class's
/// concern anymore — that lives in `AllBox`'s internal flush coordinator,
/// shared across every [AllBoxStorage] implementation.
///
/// **PT-BR:** [AllBoxStorage] baseado em disco: um container mapeia para um
/// arquivo `<container>.db` (mais os companheiros `.tmp`/`.bak`) dentro de
/// um diretório.
///
/// Reaproveita, sem mudanças, o pipeline crash-safe que o `all_box` sempre
/// usou: write-ahead em um arquivo `.tmp`, backup best-effort do `.db`
/// anterior para `.bak` (um rename, só metadata, não uma cópia de bytes),
/// depois um rename atômico de `.tmp` sobre `.db`. As leituras tentam o
/// `.db` primeiro, caem para o `.bak`, e nunca lançam exceção — qualquer
/// corrupção (arquivo ausente, UTF-8 inválido, JSON inválido) simplesmente
/// resulta em um map vazio.
///
/// Debounce, coalescing e a fila de flush não são mais responsabilidade
/// desta classe — isso vive no coordenador de flush interno do `AllBox`,
/// compartilhado por toda implementação de [AllBoxStorage].
class AllBoxIoStorage implements AllBoxStorage {
  AllBoxIoStorage({
    required this.container,
    required String directoryPath,
    bool validateContainerName = false,
  }) : _directory = Directory(directoryPath) {
    if (validateContainerName) {
      _validateContainerName(container);
    }
  }

  final String container;
  final Directory _directory;

  File get _dbFile =>
      File('${_directory.path}${Platform.pathSeparator}$container.db');

  File get _tmpFile =>
      File('${_directory.path}${Platform.pathSeparator}$container.tmp');

  File get _bakFile =>
      File('${_directory.path}${Platform.pathSeparator}$container.bak');

  @override
  Future<bool> hasPersistedData() async {
    return _dbFile.existsSync() || _bakFile.existsSync();
  }

  @override
  Future<Map<String, dynamic>> load() async {
    if (!_directory.existsSync()) {
      await _directory.create(recursive: true);
    }

    final fromMain = await _tryRead(_dbFile);
    if (fromMain != null) return fromMain;

    final fromBackup = await _tryRead(_bakFile);
    if (fromBackup != null) return fromBackup;

    // Neither the main file nor the backup could be read (missing, binary
    // garbage, truncated JSON, ...): start with an empty container rather
    // than crashing the app.
    if (_dbFile.existsSync() || _bakFile.existsSync()) {
      _debugLog(
        'AllBox("$container"): persisted data is corrupted or unreadable. '
        'Tried "${_dbFile.path}" and "${_bakFile.path}" and started with an '
        'empty in-memory container. Existing corrupted files were left in '
        'place until the next successful save.',
      );
    }
    return <String, dynamic>{};
  }

  /// Attempts to read and decode [file], returning `null` on *any* failure
  /// so the caller can fall back to the next candidate. Split into two
  /// explicit stages: UTF-8 decoding of the raw bytes, then JSON parsing of
  /// the resulting text — matching two different classes of on-disk
  /// corruption.
  ///
  /// **PT-BR:** Tenta ler e decodificar [file], retornando `null` em
  /// qualquer falha, para que quem chamou caia para o próximo candidato.
  /// Dividido em dois estágios explícitos: decodificação UTF-8 dos bytes
  /// brutos, depois parsing de JSON do texto resultante — cada um
  /// correspondendo a uma classe diferente de corrupção em disco.
  Future<Map<String, dynamic>?> _tryRead(File file) async {
    if (!file.existsSync()) return null;

    final List<int> bytes;
    try {
      bytes = await file.readAsBytes();
    } on FileSystemException {
      return null;
    }

    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      return null;
    }

    try {
      final dynamic decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map<dynamic, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } on FormatException {
      return null;
    }
  }

  @override
  Future<void> save(
    Map<String, dynamic> snapshot, {
    required AllBoxPersistMode mode,
  }) async {
    final fsync = mode == AllBoxPersistMode.flush;

    final String jsonText;
    try {
      jsonText = jsonEncode(snapshot);
    } on Object catch (error, stackTrace) {
      throw AllBoxStorageException(
        'AllBox("$container"): failed to encode snapshot to JSON.',
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (!_directory.existsSync()) {
      await _directory.create(recursive: true);
    }

    // 1) Write-ahead: new content always lands on a temp file first. If the
    //    process dies during this write, `container.db` is untouched.
    //    `flush: fsync` is what separates the two durability tiers.
    await _tmpFile.writeAsString(jsonText, flush: fsync);

    // 2) Preserve the last known-good file as a backup before replacing it.
    //    A rename is metadata-only (no bytes copied). `readInitial`/`load`
    //    already falls back to `.bak` when `.db` is missing or unreadable.
    if (_dbFile.existsSync()) {
      try {
        await _dbFile.rename(_bakFile.path);
      } catch (_) {
        // Best-effort: a failed backup refresh must not block the swap.
      }
    }

    // 3) Atomic swap.
    await _tmpFile.rename(_dbFile.path);
  }

  @override
  Future<void> delete() async {
    for (final file in <File>[_dbFile, _tmpFile, _bakFile]) {
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {
          // Best-effort.
        }
      }
    }
  }

  @override
  Future<void> close() async {}

  void _debugLog(Object message) {
    assert(() {
      // ignore: avoid_print
      print(message);
      return true;
    }());
  }

  static void _validateContainerName(String container) {
    final reservedWindowsNames = <String>{
      'CON',
      'PRN',
      'AUX',
      'NUL',
      for (var i = 1; i <= 9; i++) ...<String>{'COM$i', 'LPT$i'},
    };
    final baseName = container.split('.').first.toUpperCase();
    final validPattern = RegExp(r'^[A-Za-z0-9._-]+$');

    if (container.isEmpty ||
        container == '.' ||
        container == '..' ||
        container.endsWith('.') ||
        container.endsWith(' ') ||
        !validPattern.hasMatch(container) ||
        reservedWindowsNames.contains(baseName)) {
      throw ArgumentError.value(
        container,
        'container',
        'Invalid AllBox container name. Use only letters, numbers, ".", "_" '
            'or "-", do not use "."/"..", path separators, drive separators '
            'or Windows reserved device names.',
      );
    }
  }
}
