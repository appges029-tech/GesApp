# GesApp 2.2.0+41 — Corrections audit cumulatif 50 %

Base : GesApp 2.1.9+40.
Objectif : fermer les 14 anomalies encore ouvertes après l'audit cumulatif de 50 %.

## Corrections livrées

- Contrôle d'accès : plus aucune écriture métier anonyme ; les sauvegardes/imports/exports manuels sont réservés au Gestionnaire.
- Synchronisation cloud : distinction entre action utilisateur et opération système de confiance afin de conserver la réplication contrôlée pour un Administrateur en lecture seule.
- Sauvegardes : nouveau format V5 avec PBKDF2-HMAC-SHA256 (120 000 itérations) + AES-256-GCM ; restauration V1-V4 conservée.
- Sauvegarde automatique : secret migré de SharedPreferences vers flutter_secure_storage.
- Base SQLite : version 29, triggers d'invariants financiers et migration du statut patrimoine `retired` vers `out_of_service`.
- Établissement : le bouton Enregistrer persiste réellement identité, agrément et logo ; première configuration et année scolaire active gérées sans doublon.
- Reporting : règlements fournisseurs intégrés au journal, dépenses, bilan, tendances et dashboard.
- Bilan : l'année scolaire choisie est transmise au bilan et sa période devient la période initiale du rapport.
- Patrimoine : vente raccordée à la caisse et à la comptabilité ; compte d'encaissement et référence exigés.
- Patrimoine : biens sortis non réactivables par maintenance/déplacement ; inventaire clôturé en lecture seule.
- Patrimoine : vocabulaire de statuts unifié autour de `out_of_service`.
- Restauration Web : confirmation destructive + snapshot local + rollback automatique si une validation post-import échoue.
- Alertes : résolution des alertes devenues obsolètes et réutilisation stable des alertes `due_soon` pour éviter les notifications répétitives.

## Tests de non-régression ajoutés

`test/audit50_regression_test.dart` couvre notamment :
- refus des écritures anonymes ;
- refus des données sensibles à l'Administrateur ;
- persistance établissement et réutilisation de l'année active ;
- verrouillage d'un inventaire clôturé ;
- refus de maintenance d'un bien sorti ;
- cession patrimoniale vers caisse et comptabilité ;
- règlement fournisseur visible dans les rapports.

Les suites existantes `finance_repository_test.dart` et `security_hr_asset_repository_test.dart` ont été adaptées à l'authentification explicite du Gestionnaire.

## Validation effectuée dans l'environnement de correction

- analyse lexicale/délimiteurs des 26 fichiers Dart modifiés ou ajoutés : PASS ;
- validation YAML du pubspec : PASS ;
- validation syntaxique SQLite des 14 triggers : PASS ;
- smoke tests SQL sur paiements fournisseurs / cessions patrimoine / trésorerie / reporting : PASS ;
- checklist automatisée des correctifs de l'audit : 18/18 PASS.

## Limite

`flutter analyze`, `flutter test` et les builds Android/Windows ne sont pas revendiqués sur cette archive précise : Flutter n'est pas installé dans le conteneur où les fichiers ont été corrigés. Flutter 3.47.2 / Dart 3.13.2 est disponible sur le PC connecté, mais cette archive n'y a pas été transférée pendant cette passe.
