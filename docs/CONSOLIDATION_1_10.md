# GesApp — Consolidation réelle des chantiers 1 à 10

Cette archive est construite à partir de la chaîne complète des versions :
`full_fixed -> 1_2 -> 3_6 -> 7_9 -> design -> sauvegarde JSON -> interface unique Gestionnaire`, puis le support Web/CI a été fusionné par-dessus au lieu de repartir du ZIP original.

## Structure fonctionnelle officielle

- Interface unique **Gestionnaire**.
- Plusieurs comptes Gestionnaire possibles, tous avec les mêmes droits et la même interface.
- Aucun rôle Directeur/Caissier n'est utilisé pour masquer ou autoriser une fonctionnalité.

## 1. Socle données / années scolaires

- Schéma SQLite V10.
- `school_years` et `student_enrollments`.
- Historique annuel de scolarité.
- Réinscription annuelle séparée du changement de classe.
- Migration des anciens élèves vers le modèle annuel.
- Écran Années scolaires et parcours scolaire dans la fiche élève.

## 2. Sécurité / accès

- Comptes Gestionnaire avec PIN individuel haché/salé.
- Verrouillage persistant après échecs.
- Journal d'audit relié au gestionnaire authentifié.
- Migration des anciens rôles vers `manager` sans hiérarchie fonctionnelle.

## 3. Élèves / inscriptions

- Modification d'un élève existant.
- Champs administratifs étendus.
- Responsables structurés (`student_guardians`).
- Recherche élargie et historique annuel.
- Séparation réinscription / changement de classe.
- Documents et photos avec abstraction compatible Web.

À compléter dans une passe métier ultérieure : import CSV/Excel dédié et pagination serveur/DB pour des volumes très importants.

## 4. Finances avancées

- Moyens de paiement et comptes/caisses configurés en base.
- Références de transaction, téléphone payeur et opérateur.
- Sélection d'échéances dans le moteur de paiement.
- Avances transformables en avoirs (`payer_credits`).
- Remboursements partiels au niveau repository (`payment_refunds`).

À compléter : écran utilisateur dédié au remboursement partiel et workflow avancé des lots de facturation.

## 5. Caisse / trésorerie

- Comptes de caisse (`cash_accounts`).
- Sessions de caisse (`cash_sessions`).
- Ouverture, fond initial, solde théorique, comptage physique, écart et clôture.
- Interface Caisse accessible au Gestionnaire.

## 6. Dépenses

- Date réelle de dépense.
- Numéro de dépense.
- Fournisseur/bénéficiaire.
- Moyen de paiement, compte/caisse et référence externe.
- Statut d'approbation présent dans le modèle de données.

À compléter : workflow de demande/approbation, récurrence et gestion complète des pièces justificatives dans l'interface.

## 7. Sauvegarde / restauration

- Sauvegarde locale chiffrée AES-256-GCM sur plateformes fichiers.
- Inclusion base + médias référencés.
- Import/export JSON complet sur plateforme native.
- Écran Web séparé pour téléchargement/restauration JSON sans `dart:io`.
- Contrôles d'intégrité SQLite avant remplacement de la base native.

## 8. Paramètres établissement

- Logo et numéro d'agrément.
- Années scolaires.
- Création de cycles.
- Modification/désactivation des classes et capacité.
- Apparence et notifications accessibles dans Réglages.

## 9. Tableau de bord / alertes / rapports

- Montants échus séparés des montants futurs.
- Impayés et taux de recouvrement mieux définis.
- Alertes avec gravité, statut, archivage et envoi local.
- Alertes de capacité de classe.
- Rapport d'ancienneté des créances.
- Corrections de reporting et exports multiplateformes.

## 10. Build / Web / CI

- Abstraction SQLite : Android via sqflite, Desktop via sqflite_common_ffi, Web via sqflite_common_ffi_web.
- Services fichiers/PDF/images/export conditionnels pour éviter `dart:io` sur Web.
- `README_WEB.md`.
- `.github/workflows/build-web.yml` : Flutter 3.47.1, analyze, build Web, artifact, GitHub Pages.
- `WEB_BASE_HREF` paramétrable, défaut `/GesApp/`.

## Design et fonctionnement hors ligne

- Thème clair, sombre et système.
- Refonte globale Material 3.
- Notifications Android locales hors ligne avec tâche périodique.
- Le Web n'essaie pas d'exécuter les opérations de fichiers natives.

## Validation effectuée dans l'environnement de consolidation

- Fusion trois voies des modifications Web sur la version fonctionnelle la plus récente, et non sur le ZIP original.
- Recherche de marqueurs de conflit Git : aucun restant.
- `git diff --check` : aucune erreur d'espace/conflit.
- Audit des imports `dart:io` : uniquement dans des implémentations natives/IO et services non importés par les écrans Web.

Le SDK Flutter n'est pas disponible dans cet environnement. `flutter analyze`, `flutter test`, le build Android et le build Web doivent donc être exécutés par la CI avant publication.
