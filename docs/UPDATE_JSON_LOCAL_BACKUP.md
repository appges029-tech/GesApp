# GesApp — sauvegarde locale et import/export JSON complet

## Ajouts

- La sauvegarde locale chiffrée `.gesbk` passe au format **V4 / GESAPPBK4** et reste le format recommandé pour la conservation sécurisée. Elle embarque la base SQLite ainsi que les médias GesApp disponibles (photos, documents, logo et justificatifs référencés).
- Les anciennes sauvegardes V1/V2/V3 restent restaurables.
- L’écran **Sauvegarde & transfert des données** expose clairement la création/restauration locale.
- Nouvel export `gesapp-data-<date>.json` contenant toutes les tables utilisateur de SQLite.
- Le JSON inclut également, quand ils existent, les fichiers référencés par :
  - `establishments.logo_path` ;
  - `students.photo_path` ;
  - `student_documents.file_path` ;
  - `expenses.proof_path`.
- Empreinte SHA-256 intégrée au JSON pour détecter une modification/corruption avant import.
- Import transactionnel via une copie temporaire de la base actuelle : la base réelle n’est remplacée qu’après `integrity_check` et `foreign_key_check`.
- Copie de sécurité automatique `gesapp.db.before-json-import` avant remplacement.
- Les médias sont restaurés dans l’espace applicatif local et leurs chemins sont réécrits dans la base importée.
- Refus d’un JSON incomplet, d’un format inconnu ou provenant d’un schéma de base plus récent que l’application installée.

## Sécurité

Le JSON est volontairement **non chiffré** afin de rester portable et exploitable. Il peut contenir des informations personnelles, financières, des utilisateurs et des médias encodés en base64. Le fichier `.gesbk` AES-256-GCM reste donc recommandé pour l’archivage confidentiel.

## Validation recommandée

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. créer un jeu de données avec élève + photo + document + paiement + dépense ;
5. exporter JSON ;
6. modifier les données ;
7. importer le JSON ;
8. vérifier que les données et médias correspondent exactement à l’état exporté ;
9. tester un JSON volontairement modifié : l’import doit être refusé ;
10. tester la restauration `.gesbk` existante pour absence de régression.
