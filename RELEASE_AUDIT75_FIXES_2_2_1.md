# GesApp 2.2.1+42 — Corrections audit cumulatif 75 %

Base : GesApp 2.2.0+41.
Objectif : fermer les 10 constats nouveaux découverts entre 50 % et 75 % de l'audit statique.

## Corrections livrées

- Notifications : seuils et activation locale passent par des gardes métier ; l'Administrateur reste en lecture seule ; changements journalisés dans `audit_log`.
- Cycle de vie : `inactive` ne détruit plus la session locale ; sur `paused/hidden/detached`, la synchronisation est tentée avant le verrouillage et la purge de session.
- Authentification locale : la première configuration accepte désormais un mot de passe de 8 à 64 caractères ; l'écran de déverrouillage accepte mot de passe fort ou ancien PIN 4–8 chiffres.
- Appels à paiement : le PDF reprend le libellé de l'année scolaire réellement sélectionnée, y compris une année historique.
- Responsables élèves : exactement un responsable principal est maintenu lorsqu'au moins un responsable existe ; les champs hérités de l'élève sont synchronisés ; les rapports financiers lisent le principal courant.
- Pièces jointes Web : plafonds de 4 Mo pour les photos et 10 Mo pour les documents/justificatifs ; lecture par flux après contrôle de taille afin d'éviter le préchargement de fichiers arbitrairement gros.
- Dépenses récurrentes : une modification conserve l'état actif/inactif ; un changement de fréquence/jour recalcule la prochaine échéance.
- Classes : les classes désactivées restent visibles dans l'écran de gestion et peuvent être réactivées.
- Excel : les exports sont de vrais fichiers `.xlsx` OOXML via `package:excel`, et non plus du HTML renommé `.xls`.
- Tests : ajout d'une suite de non-régression Audit 75 et d'un dossier `integration_test/` couvrant le cycle de vie/verrouillage.

## Tests ajoutés

`test/audit75_regression_test.dart` couvre :
- garde Gestionnaire/Administrateur sur les paramètres de notifications ;
- mot de passe local long ;
- invariant du responsable principal ;
- conservation de l'état des modèles récurrents et recalcul d'échéance ;
- réactivation d'une classe inactive ;
- libellé d'année historique pour les appels à paiement.

`integration_test/audit75_flows_test.dart` couvre :
- déverrouillage avec mot de passe long ;
- transition `inactive` sans destruction de session ;
- transition `paused` avec verrouillage après tentative de synchronisation.

## Validation effectuée dans l'environnement de correction

- checklist structurée des 10 constats : 10/10 PASS ;
- vérification lexicale/délimiteurs des 23 fichiers Dart modifiés ou ajoutés : PASS ;
- parsing YAML du `pubspec.yaml` et version `2.2.1+42` : PASS ;
- présence de `integration_test` dans les dev_dependencies : PASS ;
- contrôles statiques ciblés sur quotas Web, `.xlsx`, années scolaires, responsables, récurrences et lecture seule : PASS.

## Limite

`flutter analyze`, `flutter test`, `flutter test integration_test` et les builds release ne sont pas revendiqués sur cette archive précise. Le SDK Flutter n'est pas disponible dans le conteneur où le correctif a été construit ; la validation Flutter réelle devra être lancée sur le poste connecté ou en CI avant diffusion terrain.
