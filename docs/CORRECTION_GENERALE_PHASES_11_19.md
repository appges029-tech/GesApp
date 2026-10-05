# GesApp — Correction générale phases 11 à 19

Version applicative : **1.0.0+11**  
Schéma SQLite : **V19**

Cette livraison poursuit directement `GesApp_correction_generale_phases_05_10.zip`.

## Phase 11 — Dossier élève et pièces obligatoires

- Nouvelle table `document_requirements`.
- Catalogue configurable des pièces du dossier depuis Réglages.
- Une pièce peut être obligatoire/facultative, active/inactive et ordonnée.
- La fiche élève calcule automatiquement la complétude du dossier et indique les pièces manquantes.
- L'ajout d'un document réutilise le catalogue configuré tout en laissant un type personnalisé.
- Les exigences documentaires sont incluses dans les exports JSON portables.

## Phase 12 — Responsables multiples

- Exploitation réelle de `student_guardians`.
- Écran dédié par élève : ajout, modification et suppression.
- Rôles : père, mère, tuteur, responsable financier, contact d'urgence, etc.
- Indicateurs responsable principal / financier / urgence.
- Le responsable principal reste synchronisé avec les anciens champs `guardian_name` / `guardian_phone` pour compatibilité.
- Impossible de supprimer le responsable principal sans en choisir un autre.

## Phase 13 — Import massif transactionnel et prévisualisation

- Analyse complète du fichier avant écriture.
- Détection des lignes invalides, doublons probables et dépassements de capacité projetés.
- Résumé avant import : total, valides, ignorées, erreurs.
- Import des lignes valides dans **une seule transaction SQLite** : une erreur inattendue provoque le rollback du lot.
- Les familles créées pendant l'import appartiennent à la même transaction, ce qui évite les familles orphelines dues à un import interrompu.
- Journalisation `bulk_import_transactional`.

## Phase 14 — Recherche et pagination

### Élèves
- Pagination serveur par lots de 100.
- Recherche et filtres existants conservés.
- Chargement progressif plutôt que chargement intégral.

### Paiements
- Recherche par reçu, élève, famille, montant et référence de transaction.
- Navigation paiements actifs / annulés.
- Pagination par lots de 75.

### Dépenses
- Recherche par numéro, description, bénéficiaire et référence externe.
- Filtrage par statut d'approbation.
- Pagination par lots de 75.

### Audit
- Recherche texte.
- Filtrage par type d'entité et action dans le repository.
- Pagination par lots de 100.
- Index SQLite ajoutés sur dates/références importantes.

## Phase 15 — Sauvegardes automatiques et nouvelles alertes

- Planification locale native configurable : 1, 3, 7, 14 ou 30 jours.
- Conservation automatique des 10 dernières sauvegardes locales.
- Déclenchement via le travail de fond Android existant, sans réseau.
- Alerte lorsqu'aucune sauvegarde automatique récente n'existe.
- Alerte d'échéance à venir dans les trois jours.
- Alerte si `PRAGMA integrity_check` détecte une anomalie.
- La branche Web reste sans tâche de fond native ; elle conserve les sauvegardes manuelles/JSON.

## Phase 16 — Établissement et années scolaires découplés

- L'écran Établissement ne modifie plus les dates de l'année scolaire lorsqu'on corrige le téléphone, l'adresse, le logo, etc.
- Les années scolaires sont désormais administrées uniquement depuis le module Années scolaires.
- Les colonnes historiques de la table `establishments` sont maintenues comme cache de compatibilité lors de l'activation d'une année.

## Phase 17 — Administration complète des cycles

- Consultation des cycles actifs et inactifs.
- Renommage.
- Ordre d'affichage configurable.
- Activation/désactivation.
- Protection : un cycle possédant encore des classes actives ne peut pas être désactivé.

## Phase 18 — Renforcement PIN et récupération

- Nouveau stockage PIN : **PBKDF2-HMAC-SHA256, 120 000 itérations**.
- Les comptes existants SHA-256 restent compatibles et sont automatiquement renforcés lors de la prochaine authentification réussie.
- Génération d'un code de récupération à usage contrôlé.
- Le code de récupération est lui-même dérivé par PBKDF2 et n'est jamais enregistré en clair.
- Réinitialisation du PIN via le code puis invalidation du code utilisé.
- Blocage persistant après tentatives erronées conservé.

## Phase 19 — Audit et diagnostic renforcés

Nouveaux contrôles du diagnostic :

- plusieurs sessions ouvertes sur la même caisse ;
- cohérence du statut des dépenses approuvées ;
- inscriptions annuelles orphelines ;
- comptes encore sur l'ancien algorithme PIN ;
- élèves auxquels il manque des pièces obligatoires configurées.

Le journal d'audit bénéficie également de recherche/pagination et de nouveaux index.

## Migration SQLite

- **V18** : création de `document_requirements` et valeurs initiales.
- **V19** : métadonnées de sécurité PIN (`pin_algorithm`, `pin_iterations`, récupération), plus index de recherche/audit.

Une simulation locale de migration **V17 → V19** a été exécutée sur SQLite :

- `PRAGMA integrity_check = ok` ;
- aucune violation de clé étrangère détectée.

Le schéma V19 complet a également été créé dans une base SQLite vide avec succès.

## Compatibilité JSON

`document_requirements` rejoint la liste canonique des tables portables. Elle n'est volontairement pas marquée obligatoire afin que les anciens exports JSON restent importables ; une base V19 peut recréer les valeurs par défaut après migration.

## Validation restante

L'environnement de génération utilisé pour cette correction ne contient pas le SDK Flutter. La validation finale doit donc être effectuée par GitHub Actions :

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --release
flutter build web --release
```

Aucune fonctionnalité des phases 1 à 10 n'a été retirée.
