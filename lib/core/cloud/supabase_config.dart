import 'package:flutter/foundation.dart';

class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: '',
  );
  static const publishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: String.fromEnvironment('SUPABASE_ANON_KEY'),
  );
  static const redirectUrl = String.fromEnvironment(
    'SUPABASE_REDIRECT_URL',
    defaultValue: 'com.godfirst.gesapp://login-callback/',
  );

  /// `SUPABASE_ANON_KEY` remains supported for older Supabase projects and
  /// local builds. New builds should pass `SUPABASE_PUBLISHABLE_KEY`.
  static bool get isConfigured =>
      url.trim().isNotEmpty && publishableKey.trim().isNotEmpty;

  /// Android/iOS/macOS peuvent revenir directement dans l'application.
  /// Sur Windows, Linux et Web, la confirmation est terminée dans le
  /// navigateur puis l'utilisateur revient se connecter dans GesApp.
  static String? get emailConfirmationRedirect {
    if (kIsWeb) return null;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        return redirectUrl;
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return null;
    }
  }
}
