# GesApp 1.7.0 — Comptabilité, phase 2 (50 %)

## Périmètre livré

- Comptabilité d’engagement des frais scolaires : la génération d’une échéance constate désormais une créance famille/élève (411100) et un produit scolaire (706100).
- Encaissements affectés : débit trésorerie, crédit créance ; les paiements non affectés restent traités comme encaissements directs.
- Migration V25 → V26 : reconstruction des écritures comptables dérivées afin d’éviter le double comptage des produits.
- Factures fournisseurs : enregistrement de la dette à réception (charge / 401100), suivi du solde et règlements séparés.
- Écritures manuelles contrôlées : minimum deux lignes, une seule colonne débit/crédit par ligne, équilibre obligatoire avant comptabilisation, journal d’audit.
- Rapprochements banque/Mobile Money : période, solde relevé, solde comptable, écart, pointage ligne par ligne et validation seulement lorsque toutes les écritures sont pointées.
- Paramétrage comptable : comptes de créances, produits scolaires, fournisseurs et comptes de trésorerie configurables.
- Sauvegarde/import JSON étendus aux tables de la phase 2.

## Journaux complémentaires

- VE : ventes / facturation scolaire.
- AC : achats / factures fournisseurs.
- OD : opérations diverses et écritures manuelles.
- CA, BQ, MM, TR : caisse, banque, Mobile Money et transferts.

## Contrôles

Les données sources (échéances, paiements, dépenses, factures fournisseurs) restent séparées des écritures comptables. Une source ne produit qu’une écriture principale et les écritures manuelles sont auditées.
