# GesApp — Refonte UI globale & notifications locales offline

## Refonte visuelle
- Nouvelle palette premium bleu profond / accent vert, surfaces neutres et meilleur contraste.
- Material 3 harmonisé : cartes, formulaires, boutons, dialogues, chips, navigation et typographie.
- Mode clair, mode sombre et mode système persistants dans `app_settings`.
- Sélecteur d'apparence dans Réglages + bascule rapide depuis le tableau de bord.
- Navigation mobile allégée (libellé uniquement sur l'onglet sélectionné quand 6 entrées sont visibles).
- Navigation desktop remaniée avec identité GesApp.
- Tableau de bord entièrement retravaillé : carte de solde, KPI responsives, hiérarchie visuelle et recouvrement.
- Écrans Réglages et Notifications modernisés.

## Notifications 100 % hors ligne
- `flutter_local_notifications` affiche des notifications Android locales, sans serveur ni Internet.
- `workmanager` exécute un contrôle périodique en arrière-plan (6 h, sans contrainte réseau).
- Alertes actuellement publiées : impayés et capacités de classes, avec niveaux de gravité.
- Une alerte n'est envoyée qu'une fois, puis renvoyée si sa gravité augmente (ex. 30 j / 90 j de retard) ou si une classe passe de presque pleine à complète.
- Permission Android 13+ `POST_NOTIFICATIONS` ajoutée.
- L'autorisation applicative peut être désactivée dans Réglages > Notifications hors ligne.
- Bouton de test intégré.
- Permission INTERNET retirée du manifeste Android pour ce mécanisme : aucune connexion n'est nécessaire.

## Base de données
- Schéma V9.
- Ajout `alerts.notification_sent` pour éviter les doublons de notifications locales.

## Validation requise
Exécuter sur la CI / poste Flutter :
1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. `flutter build apk --release`
5. Installer sur Android 13+ et accepter la permission de notification.
6. Tester mode clair/sombre, redémarrage de l'app, notification de test, et exécution WorkManager après fermeture de l'app.

> Android peut retarder les tâches de fond en fonction de Doze/économie de batterie. Le système reste 100 % offline, mais n'est pas un service temps réel garanti à la seconde.
