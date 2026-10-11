# GesApp — Schéma et biométrie Android (implémentation)

## Emplacement et fonctionnement
- Réglages > Sécurité & données > **Schéma et empreinte**.
- Disponible exclusivement sur Android, après authentification Supabase
  vérifiée, pour le compte et l'établissement actuellement connectés.
- L'activation et la suppression demandent le **mot de passe Supabase actuel**.
  Vérification depuis un client Supabase séparé, sans modifier la session active.
- Schéma 3×3 de **six points minimum**, deux dessins identiques pour l'activer.
- Empreinte/biométrie : fenêtre biométrique native Android, `biometricOnly: true`.
  Le PIN de l'écran verrouillé n'est pas accepté comme biométrie.
- Les profils de raccourcis sont conservés **uniquement** dans le
  `FlutterSecureStorage` local, sous une clé dérivée de
  `organizationId:cloudUserId`; pas dans SQLite, les exports JSON,
  les snapshots cloud ni Supabase.
- Schéma : sel aléatoire et PBKDF2-HMAC-SHA256 à 180 000 itérations,
  comparaisons de hash sur octets; 5 erreurs bloquent le schéma pendant
  5 minutes, même après redémarrage.
- Une rotation du mot de passe gestionnaire invalide le profil rapide de
  ce compte sur l'appareil courant.

## Parcours
- **En ligne :** `TenantAccessGate` authentifie le compte, vérifie le
  tenant et l'abonnement, puis `QuickUnlockGate` protège `HomeShell`.
  Le verrouillage s'active lors du passage en arrière-plan si un raccourci
  est configuré. Le bouton « mot de passe principal » déconnecte Supabase
  et revient au parcours normal.
- **Hors ligne :** `AppLockGate/LockScreen` conserve l'accès par mot de passe.
  Un bouton « schéma ou empreinte » est proposé seulement si le profil lié au
  gestionnaire autorisé du même établissement est enregistré. La vérification
  contrôle l'abonnement local, la classe de rôle, le tenant et l'identité
  avant d'ouvrir une session `manager` ; aucune élévation vers `admin`.
- **Web, Windows, iOS :** le raccourci n'est pas activé. Les anciennes
  méthodes de connexion sont conservées.

## Compatibilité technique
- `local_auth: ^3.0.2`, Android API 24+, Flutter >=3.29/Dart >=3.7.
- `MainActivity` étend `FlutterFragmentActivity`, manifeste avec
  `USE_BIOMETRIC`, `Theme.AppCompat.DayNight.NoActionBar`.
- Le `pubspec.lock` doit être régénéré lors d'une validation manuelle
  via `flutter pub get`, puisque la nouvelle dépendance n'existait pas.
- Aucun changement de schéma SQL/Supabase requis.

## Limites à connaître
- La biométrie native valide une empreinte enregistrée sur **l'appareil**,
  pas l'identité nominative de la personne ayant posé son doigt. Ne pas
  activer sur des appareils partagés entre plusieurs employés.
- La version utilise `local_auth` + stockage sécurisé du profil, **pas une
  opération cryptographique Android Keystore avec CryptoObject**. L'ajout
  d'un challenge matériel et l'invalidation native automatique à l'ajout
  d'une empreinte restent des renforcements futurs.
- Une révocation distante ne peut pas parvenir à un appareil totalement
  déconnecté : la date d'expiration d'abonnement locale continue d'être
  contrôlée. Changement obligatoire connu localement => aucun raccourci.
- Le mot de passe principal reste obligatoire pour activer/supprimer
  les méthodes rapides, administrer les comptes et confirmer les
  opérations sensibles. Le schéma n'est pas une connexion Supabase.

## Tests manuels obligatoires avant distribution
1. Android : écran de schéma à 9 points, dessin de moins de six points,
   erreur de confirmation, blocage cinq essais, suppression du schéma.
2. Android : appareil avec/sans biométrie enregistrée ; refus du dialogue
   natif ; biométrie impossible ; verrouillage après arrière-plan.
3. Vérifier le même gestionnaire **en ligne puis hors ligne**.
4. Basculer vers un autre compte / une autre école : aucun raccourci
   du compte précédent n'est accessible.
5. Expiration d'abonnement hors ligne, gestionnaire désactivé,
   changement de mot de passe obligatoire, téléphone partagé :
   le raccourci ne doit jamais contourner ces protections.
6. Compilation `flutter analyze`, `flutter test`, `flutter build apk`,
   `flutter build web` et Windows sur branche `main`.

## Publication contrôlée
Tous les workflows GitHub sont `workflow_dispatch`. Ne rien lancer
automatiquement sur PR ou merge : le propriétaire déclenchera les tests
et compilations à la fin de ses évolutions. Aucun compte ou donnée réelle
ne doit être manipulé pour tester cette fonctionnalité.
