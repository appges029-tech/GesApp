# Design et notifications Windows — GesApp 1.5.1+18

## Refonte visuelle

- Palette alignée sur l’identité GesApp : bleu `#1877F2`, bleu nuit
  `#0B1F3A`, accents dorés et arrière-plan clair `#F3F6FB`.
- Surfaces, cartes, champs, dialogues et feuilles modales harmonisés.
- Ombres légères sur les cartes en mode clair.
- Transitions de pages plus fluides et discrètes.
- Navigation Windows plus nette, avec panneau latéral blanc, ombre douce et
  identité bleu nuit → bleu électrique.
- Navigation mobile simplifiée à cinq entrées : Accueil, Élèves, Finances,
  Rapports et Plus.
- Le menu Plus regroupe Dépenses, RH, Patrimoine et Réglages dans une grille
  lisible, au lieu de compresser huit destinations dans la barre inférieure.
- Les thèmes clair et sombre restent entièrement pris en charge.

## Correction des notifications Windows

La cause était une restriction explicite du service à Android. Le service :

- détecte maintenant Android et Windows ;
- initialise `WindowsInitializationSettings` avec une identité GesApp stable ;
- fournit `WindowsNotificationDetails` lors de chaque envoi ;
- publie les alertes en attente sur Windows pendant l’utilisation de GesApp ;
- permet un test immédiat depuis Réglages > Notifications ;
- affiche l’erreur réelle si Windows refuse l’initialisation ou l’envoi ;
- indique dans l’interface la plateforme détectée.

Les alertes restent disponibles dans le centre interne GesApp, même si
l’utilisateur désactive les notifications système de Windows.

## Test Windows

1. Ouvrir Réglages > Notifications hors ligne.
2. Vérifier que « Plateforme détectée : Windows » est affiché.
3. Activer les alertes GesApp.
4. Cliquer sur « Tester une notification ».
5. Vérifier la bannière Windows puis le centre de notifications.
6. Si aucune bannière n’apparaît, vérifier dans Paramètres Windows > Système >
   Notifications que GesApp et les notifications globales sont autorisés, et
   que le mode Ne pas déranger est désactivé.

Windows ne prend pas en charge les répétitions périodiques du paquet de
notifications utilisé. GesApp évite donc cette API : les alertes sont
rafraîchies au démarrage, lors du chargement du tableau de bord et à
l’actualisation du centre de notifications.
