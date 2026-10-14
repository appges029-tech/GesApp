/// Converts common technical failures into actionable user-facing messages.
/// Detailed diagnostics remain available in the existing technical logs.
abstract final class FriendlyError {
  static String message(Object error) {
    final detail = error.toString().trim();
    final lower = detail.toLowerCase();
    if (lower.contains('sqlite_busy') || lower.contains('database is locked')) {
      return 'Les données sont momentanément occupées. Attendez quelques secondes puis réessayez.';
    }
    if (lower.contains('socketexception') || lower.contains('network') ||
        lower.contains('failed host lookup') || lower.contains('connection refused')) {
      return 'La connexion n’est pas disponible. Vérifiez Internet et réessayez.';
    }
    if (lower.contains('unique constraint') || lower.contains('already exists')) {
      return 'Cet élément existe déjà. Recherchez-le avant de recommencer.';
    }
    if (lower.contains('unauthorized') || lower.contains('permission denied') ||
        lower.contains('forbidden') || lower.contains('access denied')) {
      return 'Votre compte n’est pas autorisé à effectuer cette action.';
    }
    if (lower.contains('format exception') || lower.contains('formatexception')) {
      return 'Vérifiez les valeurs saisies et réessayez.';
    }
    if (lower.startsWith('bad state:')) {
      return detail.substring('Bad state:'.length).trim();
    }
    if (lower.startsWith('invalid argument(s):')) {
      return detail.substring('Invalid argument(s):'.length).trim();
    }
    return 'Une erreur est survenue. Vérifiez les informations puis réessayez.';
  }
}
