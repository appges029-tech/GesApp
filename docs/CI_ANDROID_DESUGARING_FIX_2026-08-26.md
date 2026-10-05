# Correctif CI Android — core library desugaring

Le build Release Android échouait sur `:app:checkReleaseAarMetadata` car `flutter_local_notifications` exige le core library desugaring.

Correctif appliqué dans `android/app/build.gradle` :

- `coreLibraryDesugaringEnabled true` dans `compileOptions` ;
- dépendance `com.android.tools:desugar_jdk_libs:2.1.4`.

Aucune logique Flutter ou fonctionnalité métier n'a été modifiée.
