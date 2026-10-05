# GesApp — Chantiers 7 à 9

## 7. Sauvegarde, restauration et intégrité
- Nouveau format de sauvegarde `GESAPPBK3`.
- Chiffrement authentifié AES-256-GCM via `cryptography`.
- Sauvegarde de la base SQLite + photos + documents stockés sous `GesApp/students`.
- Restauration avec contrôle SQLite, copie de sécurité et reliaison des chemins média sur le nouvel appareil.
- Compatibilité de lecture conservée avec les anciennes sauvegardes V1/V2.

## 8. Paramètres et configuration
- Numéro d’agrément rendu saisissable.
- Logo d’établissement sélectionnable depuis l’interface.
- Création de cycles depuis l’application.
- Modification du nom/capacité et désactivation d’une classe.
- Audit des changements de cycles/classes conservé.

## 9. Rapports, tableau de bord et alertes
- Tableau de bord corrigé : taux de recouvrement calculé sur les montants arrivés à échéance, distinction impayés échus / montants à venir.
- Compteur élèves aligné sur l’année scolaire active lorsqu’elle existe.
- Alertes enrichies avec gravité, état, ancienneté des impayés et classe concernée.
- Alerte de classe presque pleine/complète.
- Actions « tout marquer comme lu » et archivage.
- Nouveau rapport d’ancienneté des impayés 0–30 / 31–60 / 61–90 / 90+ jours.
- Jointure établissement des factures corrigée pour supprimer la jointure croisée `ON 1=1`.

## Migration
- Base SQLite : V7 -> V8.
- Ajout `severity` et `status` à `alerts`, avec index de recherche.

## Validation à effectuer en CI
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- Build APK Android
- Test terrain de sauvegarde/restauration entre deux appareils avec photos/documents.
