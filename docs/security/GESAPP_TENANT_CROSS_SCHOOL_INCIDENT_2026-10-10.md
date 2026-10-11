# Incident d'isolation des écoles — GesApp — 10 octobre 2026

## Constat prouvé
- Une seule base locale `gesapp.db` était ouverte quelle que soit l'école authentifiée.
- La méthode `applyOrganizationIdentity` pouvait remplacer le nom de l'établissement sans isoler ses tables métier.
- Les appareils portant un même `device_key` ont été utilisés dans Gustave Flaubert et CS Mageste.
- Les politiques Supabase de `sync_metadata` et `storage.objects` filtrent déjà par appartenance au tenant : le risque est un mélange **avant** l'envoi, dans SQLite.
- L'identité des contenus chiffrés ne peut être établie qu'après déchiffrement et vérification des `establishments`.

## Containment appliqué en production
Deux politiques RLS **restrictives** nommées :
- `public.sync_metadata.gesapp_incident_quarantine_sync`
- `storage.objects.gesapp_incident_quarantine_backups`

Elles refusent temporairement aux comptes `authenticated` les lectures et écritures des deux tenants :
- Gustave Flaubert : `b38efacc-4fa1-4ffe-8989-e936a90fc197`
- CS Mageste : `98286bee-529c-4f00-8272-3b5b178105b3`

Aucune table scolaire, sauvegarde ni compte n'a été supprimé. Les données SQLite des appareils doivent rester intactes.

## Correctif client
1. Verrou persistant `gesapp.cloud.bound_organization_id.v1` dans `app_settings`.
2. Refus de connexion à une autre école dans une installation liée, avant cache ou synchronisation.
3. Rejet de restauration par un cache lorsque `cloudUserId` ne correspond pas au compte Supabase actif.
4. Refus de publier des données locales d'un établissement sous l'identité d'un autre.
5. Vérification de l'établissement contenu dans tout snapshot déchiffré avant import de ses données.
6. Tests unitaires sur les identités, les snapshots croisés et les réglages persistants.

## Remise en service (pas automatique)
- Diffuser les nouvelles versions Android/Windows, valider les tests de deux écoles distinctes sur des installations séparées.
- Inspecter les copies locales originales et l'intégrité/identité des deux snapshots **hors production**. Le snapshot de Mageste est suspect, mais n'a pas été déchiffré ni confirmé contaminé.
- Réparer/restaurer seulement les données que leur établissement possède, sans supprimer les originaux.
- Après validation et mise à niveau des appareils, le responsable peut lever la quarantaine par :

```sql
drop policy if exists "gesapp_incident_quarantine_sync" on public.sync_metadata;
drop policy if exists "gesapp_incident_quarantine_backups" on storage.objects;
```

Ne pas enlever ces politiques tant que de vieux clients peuvent encore synchroniser deux établissements sur une seule base.

## Limitation reconnue
La correction immédiate adopte la règle **une installation SQLite = un établissement** et bloque tout changement d'école dans cette même installation. Une future évolution peut créer des fichiers de base distincts et des clés de chiffrement distinctes par tenant, avec une migration auditée, pour prendre en charge plusieurs écoles sur un même téléphone.
