# GesApp RC — test terrain express (15 à 25 min)

Ce scénario doit être exécuté sur un téléphone Android **avant toute saisie réelle d'école**.

## Préparation

1. Installer l'APK RC.
2. Ouvrir GesApp.
3. Dans l'accueil, utiliser **Commencer la configuration**.
4. Créer un établissement de test et l'année scolaire courante.
5. Paramètres > Cycles et classes : créer `CE1-A`, capacité `2`.
6. Paramètres > Sécurité : créer un PIN de test et saisir le nom de l'opérateur.

## Élèves

1. Inscrire `TEST Alpha` dans `CE1-A`.
2. Inscrire `TEST Beta` dans `CE1-A`.
3. Tenter d'inscrire un troisième élève dans `CE1-A` : l'application doit refuser car la capacité est 2.
4. Ouvrir la fiche de `TEST Alpha`, vérifier matricule, classe et statut.

## Tarification

1. Finances > Rubriques : créer `Scolarité test` en **mensuelle**.
2. Créer `Inscription test` en **annuelle**.
3. Grille tarifaire : `Scolarité test` = `20 000 FCFA` pour le cycle de CE1-A.
4. Grille tarifaire : `Inscription test` = `15 000 FCFA` pour le même cycle.
5. Générer les échéances **mensuelles** du premier mois de l'année scolaire.
6. Vérifier dans Impayés que seules les échéances `Scolarité test` ont été générées ; l'annuelle ne doit pas apparaître.

## Paiement partiel et annulation

1. Encaissements > nouveau paiement.
2. Choisir `TEST Alpha` ; le solde attendu doit être visible.
3. Encaisser `7 000 FCFA` en espèces.
4. Vérifier le reçu et son détail d'affectation.
5. Vérifier que le solde restant est `13 000 FCFA`.
6. Dans l'historique, annuler le paiement avec motif `Test contre-passation`.
7. Vérifier que le solde redevient `20 000 FCFA`.

## Forfait individuel

À réaliser avec une nouvelle période qui n'a pas encore d'échéances générées.

1. Finances > Forfaits : créer pour `TEST Alpha` un forfait individuel `12 000 FCFA` sur `Scolarité test`.
2. Générer la nouvelle période mensuelle.
3. Vérifier : Alpha = `12 000 FCFA`, Beta = `20 000 FCFA`.

## Dépenses et bilan

1. Dépenses : créer une catégorie `Test carburant`.
2. Enregistrer une dépense de `5 000 FCFA`.
3. Rapports > Bilan financier : vérifier que les dépenses et le solde changent.
4. Faire un appui long sur la dépense et l'annuler avec un motif.
5. Vérifier que le bilan ne compte plus la dépense annulée.

## Sauvegarde/restauration

1. Créer une sauvegarde avec un mot de passe de 8 caractères ou plus.
2. Ajouter ensuite une donnée de test (par exemple une nouvelle famille).
3. Restaurer la sauvegarde précédente.
4. Vérifier que la donnée créée après la sauvegarde a disparu et que les données antérieures sont présentes.
5. Essayer une restauration avec un mauvais mot de passe : la base actuelle ne doit pas être remplacée.

## Diagnostic final

Ouvrir **Paramètres > Diagnostic des données**.

**Critère de réussite : tous les contrôles doivent être validés.**

Si un seul contrôle est rouge, ne pas utiliser la RC avec des données réelles. Photographier l'écran d'erreur et conserver la sauvegarde de test pour investigation.
