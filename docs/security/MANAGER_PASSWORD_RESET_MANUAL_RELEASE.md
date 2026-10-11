# Réinitialisation du gestionnaire — livraison contrôlée

## Changements inclus

- Administrateur : code temporaire fort, masqué, révélé après confirmation,
  actualisation des comptes après succès.
- Supabase : identité de l'école, rôle, activation et abonnement vérifiés
  avant de réinitialiser un gestionnaire. L'obligation de changer son mot de passe
  est enregistrée AVANT le remplacement de l'identifiant Auth (fail closed).
- Gestionnaire : nouvelle Edge Function `manager-change-password`. Elle vérifie
  son mot de passe **actuel** via Supabase Auth, exige un nouveau secret fort et
  différent, puis efface `must_change_password` seulement après le changement
  réussi dans Auth.
- Aucun mot de passe provisoire n'est désormais stocké dans la base locale
  lors de la première connexion ; les appareils qui connaissent un changement
  obligatoire ne peuvent pas déverrouiller hors ligne ni synchroniser.
- La création d'un gestionnaire par l'administrateur n'enregistre plus son
  identité locale dans l'installation de l'administrateur.

## Workflows GitHub

Les **cinq** fichiers sous `.github/workflows/` ont uniquement :

```yaml
on:
  workflow_dispatch:
```

Aucun `push`, `pull_request`, `schedule` ou déclencheur automatique n'est
conservé. Pour les lancer : dépôt GitHub > **Actions** > sélectionner Android,
Web, Windows, APK release ou Lock Flutter dependencies > **Run workflow** >
choisir `main`.

Le build Web manuel sur `main` conserve son étape existante de publication
GitHub Pages. Ne le lancer que lorsque la publication Web est voulue.

## Ordre de déploiement (pour ne pas casser l'ancienne application)

1. Déployer les Edge Functions :
   `manager-change-password` (nouvelle) et
   `admin-reset-manager-password` (mise à jour).
2. À la date choisie, lancer **manuellement** les workflows souhaités sur
   `main` ; vérifier analyse, tests et build. Distribuer les nouveaux APK/EXE
   aux appareils avant toute restriction du RPC hérité.
3. Appliquer la migration `20261012_gesapp_manager_password_change_guards.sql`
   seulement lorsque les appareils nécessaires utilisent le nouveau client.
   Elle retire aux utilisateurs ordinaires le droit d'appeler
   `mark_password_changed()` et bloque le cloud pour un gestionnaire dont le
   changement de mot de passe est obligatoire.
4. Vérifier séparément un gestionnaire neuf, un gestionnaire réinitialisé,
   un administrateur sans abonnement, un autre établissement, et une bascule
   hors ligne/après reconnexion.
5. Surveiller les journaux Supabase. Conserver les quarantaines Gustave
   Flaubert et CS MAGESTE : ce déploiement ne les retire pas.

## Limites de sécurité

Une installation **totalement hors ligne** ne peut pas recevoir immédiatement
une révocation Supabase ; elle pourra encore utiliser un ancien secret local
jusqu'à sa prochaine communication avec le serveur si elle n'a pas connaissance
de la réinitialisation. La solution ne prétend donc pas révoquer instantanément
tous les accès locaux déconnectés. La nouvelle connexion en ligne recrée un
cache local vérifié avec le nouveau mot de passe.

Les sessions JWT encore valides peuvent subsister durant leur durée de vie.
L'étape serveur `must_change_password` et la restriction RLS de la migration
protègent l'accès au cloud via les helpers concernés après déploiement.

## Contrôles requis

- Ne pas utiliser les comptes réels pour simuler le reset.
- Valider les scénarios d'erreur (mot de passe faible, autre école, compte
  désactivé, abonnement expiré, mauvais ancien mot de passe, erreur Auth).
- Aucun workflow ne doit apparaître à la seule ouverture d'une PR ou à un push.
- Cette branche n'a pas été validée par CI, conformément à la demande du
  propriétaire ; une compilation manuelle reste nécessaire.
