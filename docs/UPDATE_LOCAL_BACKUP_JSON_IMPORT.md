# GesApp — Sauvegarde locale complète et transfert JSON

## Ajouts

- La sauvegarde locale chiffrée `.gesbk` continue d'utiliser AES-256-GCM.
- Elle embarque maintenant, en plus de SQLite et des médias élèves historiques, tous les fichiers existants référencés par des colonnes `*_path` (logo d'établissement, justificatifs, photos, documents, etc.).
- Un export complet `.json` est disponible depuis Réglages > Sauvegarde.
- Le JSON contient toutes les tables applicatives, la version du schéma, la date de création et tous les fichiers référencés encodés en Base64.
- L'import JSON affiche un aperçu avant confirmation : schéma, nombre de tables, lignes et fichiers.
- L'import est un remplacement complet des données, pas une fusion implicite.
- Une copie de sécurité locale `gesapp.db.before-json-import` est créée avant chaque import.
- Le JSON est contrôlé avant import (signature de format GesApp, tables essentielles, version de schéma, intégrité SQLite et clés étrangères).
- Les chemins de fichiers sont recréés dans le stockage interne de GesApp après import afin qu'un JSON provenant d'un autre appareil reste exploitable.

## Sécurité

Le JSON est volontairement lisible et **non chiffré** pour servir de format de transfert et d'interopérabilité. Il peut contenir des données personnelles et financières. La sauvegarde `.gesbk` reste le format recommandé pour l'archivage sécurisé.

## Validation à effectuer sur CI / appareil Android

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. Créer une sauvegarde `.gesbk`, restaurer sur une base de test et vérifier logo/photos/documents/justificatifs.
5. Exporter un JSON, vider/remplacer les données sur un appareil de test, importer le JSON et comparer les principaux compteurs et soldes.
6. Tester un JSON corrompu et un JSON issu d'un schéma plus récent : l'import doit être refusé sans perdre la base courante.
