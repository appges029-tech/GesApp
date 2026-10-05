# GesApp — Module Ressources humaines

Version : 1.3.0+14 — base SQLite V23

## Périmètre implémenté

Le module **RH** est intégré à l'interface unique Gestionnaire et fonctionne avec les mêmes principes que le reste de GesApp : offline-first, audit local, sauvegarde complète, export/import JSON, thèmes clair/sombre, Android/Desktop/Web.

### Personnel
- matricule automatique `EMP-AAAA-xxxxx` ;
- identité, coordonnées, photo, pièce d'identité, numéro social, contact d'urgence ;
- statuts et historique des changements ;
- recherche et filtres ;
- services et postes configurables ;
- affectations historisées, éventuellement liées à une année scolaire.

### Contrats
- CDI, CDD, vacataire, prestataire, stage ou autre ;
- période, salaire de base, poste, document et notes ;
- fermeture automatique de l'ancien contrat actif lors d'un nouveau contrat ;
- alertes locales pour les contrats expirant dans les 30 jours.

### Présence
- présent, absent, retard, permission, congé, mission, maladie ;
- une saisie par employé et par jour ;
- champs techniques disponibles pour heure d'arrivée, heure de départ, retard et observation ;
- synthèse PDF/Excel sur une période.

### Congés / permissions
- types configurables ;
- caractère rémunéré/non rémunéré ;
- justificatif obligatoire configurable ;
- demande, approbation, refus ;
- inscription automatique des jours approuvés dans les présences ;
- les congés non rémunérés sont pris en compte dans la paie.

### Paie
- périodes de paie ;
- salaire de base issu du contrat actif ;
- gains/retenues fixes ou en pourcentage ;
- retenue sur absences ;
- retenue sur congés non rémunérés ;
- récupération des avances sur salaire ;
- workflow `brouillon -> validée -> payée` ;
- bulletin PDF ;
- paiement par caisse/banque/Mobile Money selon la configuration Finance ;
- création automatique d'une dépense « Salaires du personnel » lors du paiement ;
- mise à jour automatique du solde d'avance.

### Avances sur salaire
- décaissement rattaché à un moyen de paiement et un compte ;
- prise en compte dans le solde de trésorerie ;
- récupération automatique dans les paies à hauteur de 25 % du salaire de base par période, dans la limite du solde ;
- historique des remboursements.

### Documents RH
- pièces d'identité, CV, diplômes, contrats, attestations, justificatifs de congé, etc. ;
- PDF et images ;
- stockage local natif ou données portables sur Web ;
- inclusion dans les sauvegardes et exports JSON.

### Rapports RH
- liste du personnel ;
- effectifs et masse salariale par service ;
- contrats arrivant à échéance ;
- présences/absences ;
- historique de paie ;
- congés/permissions ;
- export PDF et Excel.

### Alertes RH offline
- contrat arrivant à échéance ;
- dossier RH sans pièce d'identité ;
- paie du mois non préparée après le 20 ;
- diffusion via le système existant de notifications Android offline.

## Tables V23

`hr_departments`, `hr_positions`, `employees`, `employee_status_history`, `employee_assignments`, `employment_contracts`, `attendance_records`, `leave_types`, `leave_requests`, `salary_components`, `employee_salary_components`, `payroll_periods`, `payroll_entries`, `payroll_items`, `salary_advances`, `salary_advance_repayments`, `employee_documents`.

## Intégrations existantes conservées

- `cash_accounts` et règles d'ouverture de caisse ;
- `payment_methods` ;
- `expenses` pour les salaires payés ;
- `audit_log` ;
- `alerts` ;
- sauvegarde locale chiffrée ;
- export/import JSON multiplateforme.

## Vérifications de Release

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build web --release --base-href="/GesApp/"
```

Après migration d'une base V22, vérifier aussi dans **Réglages > Diagnostic des données** les contrôles RH : contrats actifs, calculs de paie, liaison paie/dépenses et soldes d'avances.
