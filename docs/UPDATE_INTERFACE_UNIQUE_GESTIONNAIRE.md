# GesApp — Interface unique Gestionnaire

## Principe métier corrigé
GesApp ne distingue plus de Directeur, Gestionnaire ou Caissier. Toutes les fonctions sont réalisées depuis une interface unique par le Gestionnaire.

## Modifications
- Navigation identique pour tout gestionnaire authentifié : Accueil, Élèves, Finances, Dépenses, Rapports, Réglages.
- Suppression des restrictions par rôle dans Finances, Dépenses, Caisse, années scolaires et paramètres.
- Écran de sécurité simplifié : uniquement des comptes Gestionnaire avec PIN local.
- Écran de connexion sans mention de rôle.
- Migration SQLite V10 : tous les anciens rôles sont normalisés vers `manager` et les rôles d'audit historiques vers `manager`.
- Le champ `role` reste en base uniquement pour compatibilité avec les anciennes sauvegardes/JSON. Il ne pilote plus l'interface ni les autorisations.
- Anti-brute-force du PIN et traçabilité de l'opérateur sont conservés.

## Compatibilité
Les anciennes bases contenant `director`, `manager` ou `cashier` sont migrées automatiquement au premier démarrage de la V10.
