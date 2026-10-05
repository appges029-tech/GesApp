# GesApp 2.1 — Supabase multitenant

## Objectif

GesApp reste **offline-first** : toutes les données métier vivent dans SQLite sur l'appareil. Supabase n'est pas une copie table-par-table de la base scolaire. Il fournit :

- l'identité cloud ;
- le tenant (établissement) ;
- les comptes Administrateur/Gestionnaire ;
- les règles RLS d'isolation ;
- un snapshot cloud chiffré de l'établissement ;
- les métadonnées de révision utilisées pour empêcher un appareil ancien d'écraser une version plus récente.

## Rôles

### Administrateur

La première personne authentifiée avec son e-mail et son mot de passe qui crée
un établissement devient `admin`.

Elle peut :
- consulter toutes les données ;
- consulter les rapports, l'audit et la synchronisation ;
- créer, désactiver/réactiver et réinitialiser les comptes gestionnaires.

Elle ne peut pas :
- modifier les élèves ;
- enregistrer/modifier des paiements ;
- modifier les dépenses, RH, patrimoine ou comptabilité ;
- publier un snapshot métier dans Supabase Storage.

Le blocage est appliqué dans les repositories métier, pas seulement dans l'interface.

### Gestionnaire

Le gestionnaire est créé par l'administrateur avec un identifiant et un mot de passe temporaire. Il se connecte avec :

1. code établissement ;
2. identifiant ;
3. mot de passe.

Au premier accès, le mot de passe temporaire doit être remplacé.

## Déploiement Supabase

1. Créer un projet Supabase.
2. Dans **Authentication > Providers > Email**, activer le provider e-mail et
   laisser la confirmation d’e-mail activée. GesApp n’utilise pas Google OAuth.
3. Dans **Authentication > URL Configuration**, ajouter les URL de retour
   utilisées par les plateformes mobiles, notamment :
   `com.godfirst.gesapp://login-callback/`.
4. Exécuter la migration dans le SQL Editor ou avec la CLI Supabase :
   `supabase/migrations/20260908_gesapp_multitenant.sql`.
5. Créer/déployer les Edge Functions :
   - `admin-create-manager`
   - `admin-disable-manager`
   - `admin-reset-manager-password`
6. Dans les secrets des Edge Functions (jamais dans les secrets de build
   Flutter), définir `SUPABASE_SECRET_KEY` ou `SUPABASE_SERVICE_ROLE_KEY`.
   `SUPABASE_URL` et `SUPABASE_ANON_KEY` sont fournis par l’environnement
   Supabase aux fonctions déployées.

> Les secrets GitHub ne configurent que le binaire Flutter : ils ne créent ni
> tables, ni bucket, ni fonctions sur le projet Supabase. Les étapes 4 à 6 sont
> donc obligatoires avant le premier usage. La migration crée les tables, les
> RPC, les politiques RLS et le bucket privé `gesapp-backups`.

## Compilation GesApp

La clé publique peut être injectée à la compilation :

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://VOTRE-PROJET.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
```

Optionnel :

```bash
--dart-define=SUPABASE_REDIRECT_URL=com.godfirst.gesapp://login-callback/
```

**Ne jamais mettre une clé secrète / `service_role` dans Flutter.**

## Synchronisation snapshot

Sur Android/iOS/Windows/macOS/Linux :

- tentative immédiate après connexion ;
- tentative toutes les 10 minutes tant que GesApp est actif ;
- tentative au retour au premier plan ;
- tentative opportuniste au passage en arrière-plan ;
- aucun upload si les données métier n'ont pas changé ;
- le gestionnaire publie le snapshot ;
- l'administrateur peut uniquement recevoir la version cloud ;
- le fichier distant est `gesapp-backups/<organization_id>/current.gesync` ;
- l’export complet est compressé puis chiffré en AES-256-GCM avant envoi ;
- le hash SHA-256 et la révision sont stockés dans `sync_metadata`.

La sauvegarde inclut l'export complet GesApp, y compris les pièces encodées par le service JSON existant. Les tables de session locale (`app_users`, `cloud_tenant_cache`, `cloud_sync_state`) restent propres à l'appareil lors d'une restauration.

### Conflits

Si le cloud a avancé alors que l'appareil contient aussi des changements locaux, GesApp **bloque l'écrasement** et signale un conflit. Il ne choisit jamais silencieusement « le dernier upload gagne ».

Cette première architecture vise la sauvegarde/synchronisation de l'état complet de l'établissement, et non l'édition concurrente transaction par transaction. Pour de la saisie simultanée intensive sur plusieurs appareils, une phase ultérieure pourra synchroniser un journal d'opérations sans déplacer toute la base SQLite dans Supabase.

## Web

L'authentification multitenant fonctionne avec Supabase Flutter sur le Web. Dans cette livraison, le service de snapshot complet est volontairement limité aux plateformes IO, car la base locale Web et les fichiers nécessitent une stratégie de sérialisation distincte. GesApp ne doit pas annoncer une sauvegarde cloud Web comme réussie tant qu'elle n'est pas réellement disponible.

## Sécurité

- Bucket Storage privé.
- RLS activé sur `organizations`, `organization_members` et `sync_metadata`.
- Un utilisateur ne peut lire que son tenant.
- Seul un `manager` actif peut écrire le snapshot.
- L'admin gère les comptes via Edge Functions, pas via une clé privilégiée embarquée.
- Un compte désactivé cesse d'être membre actif du tenant et ne satisfait plus les politiques RLS.
