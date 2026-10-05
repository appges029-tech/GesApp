# Vérification — GesApp 2.1.8 POS Receipts

## Contrôles exécutés dans cet environnement

- Vérification des imports relatifs des fichiers POS modifiés/ajoutés : OK.
- Vérification statique des délimiteurs Dart sur les fichiers modifiés : OK.
- Présence des formats A5, POS 80 mm et POS 58 mm : OK.
- Présence de la sélection/mémorisation d'imprimante POS : OK.
- Présence de l'impression directe avec repli vers le dialogue système : OK.
- Protection contre la redirection silencieuse vers une autre imprimante : OK.
- Impression automatique conditionnée à une imprimante explicitement configurée : OK.
- Réimpression A5 / POS 80 / POS 58 depuis Encaissements : OK.
- Référence de transaction reprise lors de la réimpression quand elle existe : OK.
- Espaces métier `lib/data/repositories` et `lib/core/db` : identiques au projet source.
- Aucune nouvelle dépendance ajoutée au `pubspec.yaml`.

## Vérifications non exécutables ici

Cet environnement ne fournit ni `flutter` ni `dart`. Les commandes suivantes n'ont donc pas été exécutées et doivent être lancées sur la machine Flutter de compilation :

```bash
flutter pub get
flutter analyze
flutter test
flutter build windows
```

## Validation matérielle recommandée

1. Installer/configurer le pilote Windows de l'imprimante thermique.
2. Dans GesApp : Réglages > Reçus & imprimante POS.
3. Choisir POS 80 mm (recommandé) ou POS 58 mm.
4. Choisir explicitement l'imprimante POS.
5. Lancer « Imprimer un ticket test ».
6. Vérifier la largeur, la coupe papier et les marges du pilote.
7. Activer ensuite l'impression automatique si souhaité.
