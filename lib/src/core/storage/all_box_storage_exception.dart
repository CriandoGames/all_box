/// Thrown by an [AllBoxStorage] implementation (or by the platform storage
/// resolver) when something goes wrong that the caller needs a clear,
/// actionable message about: an unsupported platform, a missing `path` on
/// IO, a JSON encoding failure, or a browser storage failure (unavailable,
/// quota exceeded, etc).
///
/// **PT-BR:** Lançada por uma implementação de [AllBoxStorage] (ou pelo
/// resolvedor de storage de plataforma) quando algo dá errado e quem chamou
/// precisa de uma mensagem clara e acionável: uma plataforma não suportada,
/// um `path` ausente no IO, uma falha ao codificar JSON, ou uma falha no
/// storage do navegador (indisponível, quota excedida, etc).
class AllBoxStorageException implements Exception {
  AllBoxStorageException(this.message, {this.cause, this.stackTrace});

  /// A human-readable, actionable description of what went wrong.
  ///
  /// **PT-BR:** Uma descrição legível e acionável do que deu errado.
  final String message;

  /// The original error that triggered this exception, if any (e.g. a
  /// [FormatException] from a failed `jsonEncode`, or a JS error caught from
  /// `localStorage`).
  ///
  /// **PT-BR:** O erro original que disparou esta exceção, se houver (ex.:
  /// um [FormatException] de um `jsonEncode` que falhou, ou um erro JS
  /// capturado do `localStorage`).
  final Object? cause;

  /// The stack trace captured alongside [cause], if any.
  ///
  /// **PT-BR:** O stack trace capturado junto com [cause], se houver.
  final StackTrace? stackTrace;

  @override
  String toString() {
    if (cause == null) return 'AllBoxStorageException: $message';
    return 'AllBoxStorageException: $message (cause: $cause)';
  }
}
