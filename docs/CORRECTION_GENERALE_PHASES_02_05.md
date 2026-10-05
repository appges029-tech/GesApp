# GesApp — Correction générale, phases 02 à 05

Base : `GesApp_correction_generale_phase_01_multi_annees.zip`

## Phase 02 — Avoirs réellement utilisables

- Ajout de `payer_credit_allocations` (V13) pour tracer chaque utilisation d'un avoir sur une échéance.
- Ajout de `FinanceRepository.applyAvailableCredit(...)` avec consommation FIFO des crédits disponibles.
- L'utilisation d'un avoir met à jour `dues.amount_paid/status` sans créer une nouvelle recette : l'argent a déjà été encaissé par le paiement source.
- L'écran de paiement affiche l'avoir disponible et permet de l'appliquer aux échéances sélectionnées.
- Les remboursements partiels savent désormais revenir sur un avoir déjà utilisé avant de revenir sur les allocations du paiement d'origine.
- L'annulation complète est bloquée si une partie de l'avoir source a déjà été consommée, afin d'éviter une contre-passation incohérente.
- Le diagnostic d'intégrité inclut les affectations d'avoirs dans la réconciliation paiement ↔ échéances.

## Phase 03 — JSON portable Android / Desktop / Web

- Ajout d'une liste canonique `gesAppPortableTables` : les tables techniques (`android_metadata`, `sqlite_sequence`, métadonnées Web…) ne sont jamais exportées ni exigées.
- Les anciens JSON qui ne contiennent pas les nouvelles tables V13/V14 restent importables ; les nouvelles tables sont alors initialisées vides.
- Les tables métier essentielles restent obligatoires afin d'empêcher les imports incomplets.
- Web utilise maintenant le même format `gesapp-json` + SHA-256 que la branche native.
- Les médias d'un JSON natif sont convertis en `data:` URLs lors d'un import Web.
- Les médias `data:` provenant du Web sont matérialisés en fichiers locaux lors d'un import Android/Desktop.
- Le backfill des années scolaires est également appliqué lors d'une restauration Web d'un ancien JSON.

## Phase 04 — Caisse réellement contraignante

- Ajout de règles communes `cash_rules.dart`.
- Une caisse de type `cash` doit être ouverte avant :
  - un encaissement espèces ;
  - un remboursement lié à cette caisse ;
  - une annulation d'encaissement ;
  - l'approbation/comptabilisation d'une dépense ;
  - l'annulation d'une dépense comptabilisée ;
  - un transfert entrant/sortant impliquant la caisse physique.
- Cohérence moyen de paiement ↔ type de compte : espèces→cash, Mobile Money→mobile, virement/chèque→bank.
- Banque/Mobile Money ne nécessitent pas d'ouverture de caisse physique.
- L'écran Caisse indique explicitement qu'une caisse fermée bloque les mouvements.

## Phase 05 — Transferts entre comptes

- Ajout de `cash_transfers` (V14).
- Transfert Caisse ↔ Banque ↔ Mobile Money sans créer de recette ni de dépense artificielle.
- Contrôle : source différente de destination, montant > 0, comptes actifs, caisse physique ouverte si concernée, solde source suffisant.
- Les transferts entrent dans le calcul du solde théorique d'une session de caisse.
- L'écran Caisse permet de saisir et consulter les transferts récents.
- Le journal de trésorerie affiche le transfert comme mouvement interne à impact global nul.
- Le diagnostic d'intégrité contrôle les transferts incohérents.

## Versions

- SQLite : V12 → V14
- Application : 0.7.0+8 → 0.8.0+9

## Validations effectuées dans l'environnement de correction

- Extraction et exécution des 50 instructions `CREATE TABLE/INDEX` du schéma : OK.
- `PRAGMA integrity_check` sur le schéma reconstruit : `ok`.
- Vérification des FK sur scénario avoir + transfert : 0 anomalie.
- Réconciliation d'un paiement de test : allocation directe + avoir disponible + avoir consommé = montant encaissé.
- Vérification structurale des 94 fichiers Dart : parenthèses/accolades/crochets équilibrés.
- Aucun marqueur de conflit Git détecté.

La validation Flutter finale reste à exécuter en CI : `flutter analyze`, `flutter test`, build Android et build Web.
