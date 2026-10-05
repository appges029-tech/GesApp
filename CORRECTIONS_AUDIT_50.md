# GesApp 2.1.3+34 — Corrections audit 50%

Cette version corrige en priorité les défauts bloquants relevés dans l’audit de GesApp 2.1.2.

## Corrigé

- 50 insertions `BusinessWriteGuard.ensureAllowed(...)` remises dans le corps des méthodes au lieu des listes de paramètres.
- Les signatures touchées dans Familles, Finances, Caisse, Dépenses, RH, Paramètres, Comptabilité, Patrimoine et Recouvrement ont été assainies.
- La publication d’un snapshot cloud utilise maintenant un chemin unique par tentative.
- Le fichier Storage n’est considéré comme courant qu’après mise à jour optimiste réussie de `sync_metadata` sur la révision attendue.
- En cas de conflit de concurrence, l’upload perdant est supprimé et ne peut plus remplacer silencieusement le snapshot valide.
- L’ancien snapshot n’est supprimé qu’après commit réussi des métadonnées.
- Le checksum SHA-256 est maintenant vérifié avant déchiffrement/restauration du snapshot.

## Encore à traiter dans la seconde moitié de l’audit

- Consolider la migration Supabase du ZIP avec l’état exact actuellement déployé.
- Tester et finaliser le retour de confirmation e-mail sur Windows.
- Lancer `dart format`, `flutter analyze`, `flutter test` et builds Android/Windows dans un environnement Flutter complet.
- Compléter les tests de concurrence multi-appareils et les tests de restauration/corruption.

## Limite de certification

Flutter/Dart n’est pas installé dans l’environnement utilisé pour cette correction. La vérification effectuée ici est structurelle et statique ; aucune réussite de compilation n’est revendiquée.
