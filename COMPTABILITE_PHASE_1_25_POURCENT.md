# GesApp 1.6.0 — Comptabilité, phase 1 (25 %)

## Périmètre livré

- Plan comptable OHADA simplifié et orienté établissement scolaire.
- Journaux CA (caisse), BQ (banque), MM (Mobile Money), TR (transferts) et OD (opérations diverses).
- Écritures automatiques en partie double issues des paiements, remboursements, dépenses approuvées, transferts et avances au personnel.
- Contre-passation automatique des paiements et dépenses annulés.
- Reprise automatique des opérations historiques sans modifier les données sources.
- Livre-journal, grand-livre et balance générale filtrables par période.
- Export PDF et Excel des quatre documents comptables.
- Sauvegarde et import JSON des nouvelles tables comptables.

## Règles de sécurité

- Une écriture comporte toujours une ligne au débit et une ligne au crédit du même montant.
- Une source métier ne peut produire qu’une seule écriture principale.
- Les écritures générées ne remplacent ni ne modifient les reçus, paiements ou dépenses d’origine.
- Les annulations sont tracées par une contre-écriture et non par la suppression de l’historique.

Cette première phase utilise une comptabilisation simplifiée des encaissements. La phase suivante devra ajouter les créances à la génération des échéances, les dettes fournisseurs, les journaux manuels contrôlés, les rapprochements bancaires et le paramétrage comptable détaillé.
