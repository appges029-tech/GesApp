# GesApp 2.1.8 — Reçus POS thermiques

## Nouveautés

- Conservation du reçu administratif A5.
- Nouveau ticket thermique POS 80 mm.
- Nouveau ticket thermique POS 58 mm.
- Impression directe sur une imprimante locale détectée par `printing`.
- Sélection et mémorisation de l’imprimante POS dans Réglages.
- Option d’impression automatique après un paiement, uniquement lorsqu’une imprimante POS explicite est sélectionnée.
- Logo, détail des affectations et 1/2 copies configurables.
- Ticket test depuis Réglages > Reçus & imprimante POS.
- Réimpression au choix en A5, POS 80 mm ou POS 58 mm depuis Encaissements.

## Compatibilité

Le format A5 reste le défaut afin de préserver le comportement des installations existantes. Une imprimante POS configurée n’est jamais remplacée silencieusement par une autre imprimante Windows si elle devient indisponible. Le mode POS est activé explicitement par le gestionnaire.

Les empreintes SHA-256 sont séparées par variante (`:pos80` / `:pos58`) afin qu’une impression POS ne remplace pas l’empreinte historique du reçu A5.

## Vérification avant production

Sur une machine avec Flutter installé :

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows
```

Puis tester physiquement une imprimante 80 mm et, si utilisée, une 58 mm avec son pilote Windows et son format papier configuré.
