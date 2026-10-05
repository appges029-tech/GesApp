# GesApp — Release Candidate 48 h P1

Date de stabilisation : 22 août 2026

## Objectif

Cette branche/Archive P1 est une étape de stabilisation Android. La priorité est l'intégrité comptable et la possibilité de faire le parcours terrain essentiel hors ligne : configuration -> classes -> élèves/familles -> tarifs/forfaits -> échéances -> paiements/reçus -> dépenses -> rapports -> sauvegarde.

## Correctifs majeurs depuis P0

### Moteur financier
- Correction d'une erreur de syntaxe résiduelle dans `recentPayments` qui pouvait empêcher la compilation.
- Séparation de la **date de référence tarifaire** et de la **date limite de paiement** lors de la génération des échéances.
- La génération refuse désormais une période située hors de l'année scolaire configurée et exige que l'établissement soit paramétré.
- Les forfaits individuels et familiaux conflictuels sur une même rubrique/période sont refusés afin d'éviter une règle de priorité ambiguë.
- Création/désactivation des rubriques et tarifs auditée.
- Reçus enrichis avec coordonnées de l'établissement et détail des échéances couvertes.
- Formulaire de paiement : affichage du solde dû et blocage préventif des surpaiements.

### Élèves et familles
- Matricules séquentiels déjà introduits en P0 conservés et reprise après le plus grand matricule existant.
- Contrôle de capacité lors de l'inscription et de la réinscription.
- Fiche élève accessible depuis la liste.
- Réinscription/changement de classe et changement de statut tracés.
- Création de famille auditée et erreurs d'inscription affichées proprement au lieu de remonter comme exceptions UI.

### Dépenses et rapports
- Catégories de dépenses créables depuis l'interface.
- Annulation d'une dépense par contre-passation logique (statut `annule`) avec motif et audit ; aucune suppression silencieuse.
- Le bilan financier affiche désormais recettes réelles, dépenses et solde de trésorerie, en plus du recouvrement.

### Alertes et audit
- Génération des alertes d'impayés déclenchée au chargement du dashboard.
- Les alertes devenues obsolètes après règlement sont automatiquement marquées comme lues.
- Écran `Journal d'audit` ajouté dans Paramètres.

### Diagnostic de données
Un écran **Paramètres > Diagnostic des données** exécute des contrôles en lecture seule :
- `PRAGMA integrity_check` SQLite ;
- clés étrangères ;
- échéances négatives/surpayées ;
- cohérence des statuts `unpaid/partial/paid` ;
- égalité paiements actifs ↔ allocations ;
- égalité `amount_paid` ↔ allocations ;
- doublons de tarifs actifs ;
- doublons de forfaits actifs ;
- rattachement des forfaits familiaux ;
- dépassement de capacité des classes ;
- matricules élèves manquants.

Aucune réparation comptable automatique n'est effectuée : une anomalie doit être examinée explicitement.

### Sauvegarde/restauration
- Format P1 avec sel aléatoire + dérivation de clé + HMAC-SHA256 pour détecter mot de passe erroné ou fichier altéré.
- Compatibilité de lecture avec les sauvegardes P0/V1 maintenue.
- Avant remplacement, la base restaurée passe `PRAGMA integrity_check`, `PRAGMA foreign_key_check` et un contrôle des tables GesApp attendues.
- Après restauration, les providers Riverpod principaux sont invalidés afin que les écrans relisent immédiatement les données restaurées.

### Android / build
- Wrapper Gradle aligné sur 8.9 pour AGP 8.7.3.
- Dépendances non utilisées retirées de la RC afin de réduire le risque de résolution/build.
- Scripts `tool/preflight_release.sh` et `tool/preflight_release.ps1` : Flutter version/doctor, `pub get`, `analyze`, `test`, puis `build apk --release`.
- GitHub Actions conserve la même chaîne de validation et publie l'APK comme artefact.
- Le démarrage Flutter n'utilise plus un binding initialisé hors de la zone de `runApp`, afin d'éviter les problèmes de zone au démarrage.

## Tests ajoutés

`test/finance_repository_test.dart` couvre notamment :
- mensuel != annuel ;
- date de référence tarifaire ;
- forfait individuel ;
- conflit forfait individuel/familial ;
- forfait familial sans double dette ;
- paiement partiel + annulation ;
- contrôle d'intégrité après contre-passation ;
- capacité maximale d'une classe.

## Contrôles statiques effectués dans l'environnement d'audit

- Tous les fichiers Dart de `lib/` et `test/` passent un contrôle lexical de chaînes/commentaires/délimiteurs.
- Tous les imports Dart relatifs pointent vers des fichiers existants.
- `pubspec.yaml` et le workflow GitHub Actions sont des YAML valides.
- Le schéma SQLite complet a été exécuté dans SQLite de contrôle.
- Toutes les requêtes SQL du nouveau diagnostic s'exécutent sur le schéma GesApp.

## Blocage restant avant de déclarer la RC utilisable

L'environnement d'audit ne contient ni Flutter SDK ni Android SDK. La validation réelle suivante reste donc obligatoire :

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --release`
5. installation sur un téléphone Android réel
6. exécution du scénario terrain décrit dans `docs/EMERGENCY_48H_PLAN.md`
7. ouverture de **Diagnostic des données** après le scénario : tous les contrôles doivent être au vert

Tant que les étapes 1 à 4 n'ont pas réussi dans un environnement Flutter réel, P1 doit rester appelée **Release Candidate**, pas version de production.
