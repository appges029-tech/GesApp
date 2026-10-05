# GesApp — plan de stabilisation 48 h

## Objectif
Livrer une version Android utilisable sur le terrain, hors ligne, avec priorité absolue à l'intégrité des données et de la comptabilité.

## Périmètre bloqué pour la release candidate

Fonctions indispensables :
- paramétrage établissement, cycles/classes ;
- inscription et liste des élèves ;
- familles ;
- rubriques et grille tarifaire ;
- forfaits individuels/familiaux liés à une rubrique ;
- génération correcte des échéances par périodicité ;
- paiements partiels, paiements familiaux et annulation tracée ;
- dépenses ;
- reçus PDF ;
- tableau de bord ;
- rapports de base ;
- PIN ;
- sauvegarde/restauration locale ;
- APK Android de validation.

Fonctions reportées après la release candidate :
- Google Drive automatique ;
- iOS/Windows ;
- dossier documentaire élève complet ;
- Excel avancé ;
- graphiques et polish UI non essentiels ;
- multi-comptes.

## Correctifs P0 intégrés

- Filtrage des échéances selon la périodicité sélectionnée.
- Ajout de la périodicité « unique » dans l'écran de génération.
- Forfaits rattachés à une rubrique et utilisés pour remplacer le tarif standard.
- Forfait familial généré comme dette familiale unique afin d'éviter la double facturation.
- Historisation minimale de la grille tarifaire : un nouveau tarif ferme le tarif actif précédent pour la même cible.
- Matricules élèves séquentiels et déterministes au lieu d'un tirage aléatoire.
- Sauvegarde/restauration effectuée base SQLite fermée, avec validation de la signature SQLite avant remplacement.
- Restauration par fichier temporaire avec copie de sécurité de la base précédente.
- Taux de recouvrement du dashboard basé sur les montants réellement alloués aux échéances.
- Compteur d'alertes du dashboard invalidé après lecture/actualisation.
- Workflow GitHub Actions de validation et build APK ajouté.

## Garde-fous avant mise en service

La release candidate n'est déclarée utilisable que si les contrôles suivants passent :
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --release`
5. installation sur un téléphone Android réel ;
6. scénario complet : école -> classe -> élève -> rubrique -> tarif -> échéance -> paiement partiel -> paiement final -> reçu ;
7. scénario forfait individuel ;
8. scénario forfait familial ;
9. annulation d'un paiement et contrôle du solde ;
10. dépense et contrôle du solde du mois ;
11. sauvegarde -> ajout de données -> restauration -> contrôle des données restaurées.

## Interdictions de release

Ne pas utiliser la version en production si :
- une génération mensuelle crée une rubrique trimestrielle/annuelle/unique ;
- un forfait génère en plus le tarif standard ;
- un paiement annulé ne rétablit pas exactement le solde ;
- une restauration échoue ou altère la base ;
- `flutter analyze`, `flutter test` ou le build APK échoue.

## Avancement P1 — 22 août 2026

La P1 ajoute la fiche/réinscription élève, la capacité des classes, le vrai bilan recettes-dépenses, l'annulation auditée des dépenses, le journal d'audit, le diagnostic d'intégrité des données, les reçus détaillés, la validation renforcée des forfaits, la séparation date tarifaire/date d'échéance, la validation complète d'une base avant restauration et les scripts de préflight Android.

Le build Flutter réel reste le prochain verrou de livraison. Après build réussi, la priorité passe immédiatement au test du scénario terrain et aux corrections issues de l'appareil, sans élargir le périmètre fonctionnel.
