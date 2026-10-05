# Modèle de données — GesApp V1

## Référentiel établissement

`establishments` contient l'identité de l'école et l'année scolaire active. `cycles` et `classrooms` structurent les niveaux et salles.

## Élèves

`students` référence éventuellement une `family` et obligatoirement une classe. `student_documents` conserve les pièces du dossier.

## Finance

`fee_categories` décrit les rubriques et leur périodicité. `fee_grid` historise les montants applicables. `packages` modélise les forfaits familiaux ou individuels. `dues` matérialise les sommes dues par période. `payments` est le journal des encaissements et `payment_allocations` indique comment chaque paiement solde une ou plusieurs échéances.

## Dépenses

`expense_categories` et `expenses` portent les sorties de caisse, avec chemin local vers un justificatif.

## Contrôle

`alerts` alimente le centre de notifications. `audit_log` conserve les modifications sensibles.

## Choix structurants

Les montants sont stockés en entiers, en unité monétaire XAF, afin d'éviter les erreurs d'arrondi flottant. Les dates sont stockées en ISO 8601. Les identifiants métier sont des UUID texte.
