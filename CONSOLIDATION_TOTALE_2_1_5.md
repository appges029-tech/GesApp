# GesApp 2.1.5+36 — Consolidation totale

Version consolidée finale issue de GesApp 2.1.4 et de l'audit complet du 8 septembre 2026.

## Inclus
- Tous les modules métier consolidés de GesApp 2.0.
- Architecture multitenant Supabase par établissement.
- Administrateur propriétaire en lecture seule sur les données métier.
- Gestionnaires créés par l'administrateur.
- Authentification administrateur par e-mail/mot de passe avec confirmation e-mail obligatoire.
- SQLite offline-first, schéma V28.
- Synchronisation cloud par snapshots chiffrés et compressés.
- Protection contre l'écrasement concurrent par révision optimiste.
- Vérification SHA-256 avant restauration.
- Bucket officiel `gesapp-backups`.
- Migration Supabase consolidée et Edge Functions de gestion des comptes.
- RLS multitenant et séparation stricte des établissements.

## État Supabase au moment de la consolidation
- Audit sécurité Supabase : aucune alerte.
- Les avertissements de performance restants sont uniquement des index encore inutilisés sur une base pratiquement vide ; ils ne sont pas des erreurs fonctionnelles.

## Certification locale à effectuer
L'environnement de génération ne dispose pas du SDK Flutter/Dart. Exécuter sur la machine de compilation :

```bash
flutter clean
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release
flutter build windows --release
```

Ne considérer les builds Android/Windows comme certifiés qu'après succès de ces commandes.
