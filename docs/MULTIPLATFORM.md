# GesApp — cible multi-plateforme

GesApp cible officiellement Android, iOS et Windows. La structure est aussi prévue pour Web, macOS et Linux.

## Adaptations intégrées

- SQLite mobile : `sqflite` sur Android/iOS.
- SQLite desktop : `sqflite_common_ffi` sur Windows/Linux.
- Navigation responsive : barre inférieure sur mobile, `NavigationRail` sur grand écran.
- PDF/impression : `pdf` + `printing`.
- Sélection de fichiers : `file_picker`.
- Stockage de chemins : `path_provider`.
- Préférences : `shared_preferences`.
- Code métier commun conservé dans `lib/`.

## Génération officielle des plateformes

Les dossiers natifs doivent être produits par le SDK Flutter officiel afin de rester compatibles avec la version de Flutter installée.

macOS/Linux :

```bash
./tool/bootstrap_platforms.sh
```

Windows PowerShell :

```powershell
./tool/bootstrap_platforms.ps1
```

La commande crée `android/`, `ios/`, `windows/`, `web/`, `macos/` et `linux/` sans remplacer la logique métier existante.

## Compilation

- Android : Windows/macOS/Linux + Android SDK.
- Windows : Windows + Visual Studio avec "Desktop development with C++".
- iOS : macOS + Xcode + signature Apple.

## Google Drive

Le cœur de GesApp reste 100 % hors ligne avec export/restauration locale. L'intégration Google Drive devra utiliser le flux OAuth adapté à chaque plateforme ; Windows nécessite une validation spécifique du flux desktop.
