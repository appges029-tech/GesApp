# GesApp 2.1.0 — Version finale + Supabase multitenant

## Mise à jour 2.1.0 — Supabase multitenant

GesApp ajoute une couche cloud sans remplacer SQLite : premier créateur de l’établissement = **Administrateur**, compte e-mail + mot de passe, lecture seule des données métier ; création de comptes **Gestionnaire** opérationnels ; isolation RLS par établissement ; snapshot chiffré et synchronisation conditionnelle toutes les 10 minutes.

Déploiement : `docs/SUPABASE_MULTITENANT_SETUP.md`. Notes de version : `docs/RELEASE_SUPABASE_2_1_0.md`.


Cette archive est la consolidation finale du périmètre GesApp. Voir `docs/FINAL_CONSOLIDATION_100.md` pour la matrice fonctionnelle complète et `docs/IMPLEMENTATION_STATUS.md` pour le statut de certification.

Base de conception et de développement Flutter pour une application de gestion scolaire offline-first.


## Configuration Supabase pour les builds GitHub Actions

Les builds de publication reçoivent la configuration Supabase via les *GitHub Actions secrets* et ne contiennent aucune valeur de secours dans le dépôt. Configurez, dans **Settings → Secrets and variables → Actions**, les secrets suivants :

- `SUPABASE_URL` : l’URL du projet Supabase (`https://<project-ref>.supabase.co`).
- `SUPABASE_PUBLISHABLE_KEY` : la clé publishable/anon du client Flutter. Pour les projets Supabase plus anciens, `SUPABASE_ANON_KEY` est aussi accepté.
- `SUPABASE_REDIRECT_URL` *(facultatif)* : l’URL de retour OAuth, par exemple `com.godfirst.gesapp://login-callback/`.

N’ajoutez jamais `service_role` ou une clé secrète Supabase aux secrets de build : une application Flutter embarque les `--dart-define` dans le binaire. La sécurité des données doit rester assurée par les politiques RLS Supabase. Les workflows échouent explicitement si l’URL ou la clé publishable manque afin d’éviter de publier une version non connectée.

Pour un lancement local, fournissez les mêmes valeurs :

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-ou-anon-key> \
  --dart-define=SUPABASE_REDIRECT_URL=com.godfirst.gesapp://login-callback/
```

## Principes

- Android en priorité, Flutter/Dart.
- Toutes les opérations quotidiennes fonctionnent hors ligne.
- SQLite local avec contraintes, transactions et journal WAL.
- Riverpod prévu pour l'état applicatif.
- Palette inspirée des couleurs Facebook : bleu `#1877F2`, fond `#F0F2F5`, surfaces blanches.
- Les transactions financières sensibles sont destinées à être auditées et non supprimées silencieusement.
- PDF pour reçus/rapports et export local/Google Drive pour les sauvegardes.

## Démarrage

```bash
flutter pub get
flutter test
flutter run
```

> Le SDK Flutter n'était pas disponible dans l'environnement de génération de ce dossier. Le projet est donc structuré et relu statiquement, mais il doit être compilé dans un environnement Flutter avant déploiement.

Voir `docs/CONCEPTION.md`, `docs/DATA_MODEL.md`, `docs/ROADMAP.md` et `docs/IMPLEMENTATION_STATUS.md`.


## Livraison finale
Voir `docs/FINAL_STATUS.md`. Les fonctions cœur V1 sont présentes dans le code source. Une compilation Flutter réelle reste requise avant APK/Play Store.

Pour produire une APK Android réellement installable, configurez la signature
privée décrite dans `docs/ANDROID_INSTALLATION.md`.


## Multi-plateforme

GesApp cible officiellement **Android, iOS et Windows**. Le code inclut SQLite desktop et une navigation responsive. Les plateformes natives officielles se génèrent avec `tool/bootstrap_platforms.sh` ou `tool/bootstrap_platforms.ps1`. Voir `docs/MULTIPLATFORM.md`.

## Mise à jour 0.9.0 — correction générale phases 06–10

Cette version ajoute les moyens de paiement/comptes configurables, les justificatifs de dépenses, la simulation et les lots de facturation, le module de recouvrement et les rapports de recouvrement par cycle/classe/rubrique. Voir `docs/CORRECTION_GENERALE_PHASES_06_10.md`.


## Ressources humaines

GesApp 1.3 ajoute un domaine RH offline complet : personnel, services/postes, contrats, affectations, présences, congés, paie, avances, documents, rapports et alertes locales. Voir `docs/RH_MODULE_IMPLEMENTATION.md`.


## Patrimoine

GesApp 1.4 ajoute un module complet de gestion du patrimoine : biens, catégories, localisations, affectations, mouvements, maintenance, inventaires physiques, sorties et rapports patrimoniaux. Voir `docs/PATRIMOINE_MODULE_IMPLEMENTATION.md`.


## Vérification des reçus
Dans **Finances > Vérifier un reçu**, le Gestionnaire peut saisir un numéro et contrôler l’authenticité et l’état du reçu, entièrement hors ligne.


## Mise à jour 1.7.0 — comptabilité à 50 %

Créances scolaires, dettes fournisseurs, écritures manuelles équilibrées, rapprochements bancaires/Mobile Money et paramétrage comptable détaillé. Voir `COMPTABILITE_PHASE_2_50_POURCENT.md`.


## Version consolidée actuelle
La distribution source de référence issue de l’audit cumulatif à 100 % est désormais **GesApp 2.2.2+43**. Voir `RELEASE_AUDIT100_FIXES_2_2_2.md` et `RELEASE_MANIFEST.md`.
