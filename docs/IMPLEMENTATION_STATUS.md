# État d’implémentation — GesApp 2.0.0

Le périmètre fonctionnel consolidé est décrit dans `FINAL_CONSOLIDATION_100.md`.

Les anciennes listes « reste à faire » présentes dans des notes de phases antérieures sont historiques et ne décrivent plus l’état courant du code. Les fonctionnalités qui y étaient citées (import CSV/Excel, remboursement partiel, workflow d’approbation, réinscription, comptes gestionnaires, dossier documentaire élève, RH, patrimoine, comptabilité d’engagement, rapprochement et rapports) sont maintenant présentes dans la base consolidée.

La seule intégration volontairement non embarquée est un client OAuth Google Drive propriétaire : GesApp reste offline-first et exporte ses sauvegardes vers les emplacements fournis par le sélecteur système, y compris les dossiers synchronisés disponibles. Un OAuth Drive automatique exige les identifiants et paramètres Google Cloud propres au déploiement.

## Validation de release

Le SDK Flutter/Dart n’étant pas installé dans l’environnement de consolidation, exécuter avant production : `flutter pub get`, `flutter analyze`, `flutter test`, puis les builds Android et Windows.
