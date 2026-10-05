# Supabase configuré pour GesApp

Projet Supabase : `layuzuqhmidwvcydvvre` (eu-west-1)

La version inclut par défaut l'URL du projet et sa clé **publishable** (clé publique destinée au client). Aucune clé secrète/service_role n'est incluse dans Flutter.

## Déjà déployé sur le projet
- Tables multitenant : organizations, organization_members, devices, sync_metadata.
- RLS d'isolation par établissement.
- Bucket privé `gesapp-backups` pour les snapshots chiffrés.
- Edge Functions JWT : admin-create-manager, admin-disable-manager, admin-reset-manager-password.
- RPC : bootstrap_organization, get_my_organization, mark_password_changed.
- Index de sécurité/performance essentiels.

## Action externe encore nécessaire pour e-mail
Dans Supabase Auth, activer le provider e-mail, conserver la confirmation
d’e-mail et autoriser le redirect :
`com.godfirst.gesapp://login-callback/`

Cette étape ne demande aucune clé secrète dans le client Flutter. Les clés
privilégiées restent réservées aux Edge Functions.


## Authentification administrateur
La connexion Google a été supprimée. L’administrateur utilise un e-mail + mot de passe. La confirmation de l’adresse e-mail est obligatoire avant la création du tenant. Les gestionnaires conservent code établissement + identifiant + mot de passe.
