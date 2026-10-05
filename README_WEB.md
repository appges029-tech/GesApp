# GesApp — Web

GesApp supporte Android, Desktop et maintenant Flutter Web.

## Prérequis

- Flutter **3.47.2 stable**
- Chrome pour le développement local

## Préparer le projet

```bash
flutter config --enable-web
# Si le dossier web/ n’existe pas dans votre copie :
flutter create --platforms=web .
flutter pub get
dart run sqflite_common_ffi_web:setup --force
```

La dernière commande génère les fichiers requis par SQLite Web dans `web/` (`sqlite3.wasm` et `sqflite_sw.js`). Elle doit être relancée après une mise à jour de `sqflite_common_ffi_web`/`sqlite3`.

## Tester localement

Pour conserver la même base IndexedDB entre les sessions de développement, utilisez de préférence toujours le même port :

```bash
flutter run -d chrome --web-port 8080
```

La commande minimale demandée reste :

```bash
flutter run -d chrome
```

## Compiler en release

```bash
flutter build web --release
```

Pour un déploiement GitHub Pages dans le dépôt `GesApp` :

```bash
flutter build web --release --base-href="/GesApp/"
```

Pour un autre nom de dépôt, remplacez `/GesApp/` par `/<nom-du-repo>/`.

## GitHub Actions / GitHub Pages

Le workflow `.github/workflows/build-web.yml` :

1. installe Flutter 3.47.2 stable avec cache ;
2. active Web et génère le scaffold `web/` s’il manque ;
3. exécute `flutter pub get` ;
4. installe le runtime SQLite Web ;
5. exécute `flutter analyze` puis `flutter test` ;
6. compile `build/web` ;
7. publie l'artifact `web-build` ;
8. déploie automatiquement `build/web` sur la branche `gh-pages` avec `peaceiris/actions-gh-pages`.

Le `base-href` peut être changé sans modifier le YAML : créez dans GitHub **Settings → Secrets and variables → Actions → Variables** une variable de dépôt :

```text
WEB_BASE_HREF=/MonAutreDepot/
```

Sans variable, la valeur par défaut est `/GesApp/`.

Ensuite, dans **Settings → Pages**, configurez la publication depuis la branche `gh-pages` (racine `/`).

## Stockage Web

- SQLite utilise `sqflite_common_ffi_web` et persiste dans **IndexedDB**.
- Les préférences simples utilisent `shared_preferences`, compatible Web.
- Les photos/pièces choisies sur Web sont conservées sous forme de données intégrées à la base, au lieu d'un chemin de fichier local.
- Les PDF et exports sont téléchargés par le navigateur. Android/Desktop conservent leurs comportements natifs.
- La sauvegarde Web utilise un export/import JSON, car il n'existe pas de chemin vers un fichier SQLite IndexedDB comparable à Android/Desktop. Les exports complets incluent un manifeste signé des tables et GesApp refuse une restauration incomplète ou provenant d'un schéma SQLite différent.

## Base href et assets

`web/index.html` utilise :

```html
<base href="$FLUTTER_BASE_HREF">
```

Flutter remplace cette valeur au build. Évitez donc les chemins absolus commençant par `/` pour les assets applicatifs ; utilisez `AssetImage('assets/...')` / `Image.asset('assets/...')` si des assets sont ajoutés plus tard.

## Compatibilité des plugins

- `flutter_riverpod`, `intl`, `uuid`, `pdf`, `crypto`, `path` : Dart/Flutter multi-plateforme.
- `printing` : supporte Web ; GesApp télécharge cependant les PDF sur Web pour avoir un comportement explicite et fiable.
- `file_picker` : supporte Web ; les APIs de sélection de dossier n'existent pas sur Web, donc elles restent réservées à Android/Desktop.
- `shared_preferences` : support Web.
- `sqflite` reste utilisé sur Android/macOS ; `sqflite_common_ffi` sur Windows/Linux ; `sqflite_common_ffi_web` sur Web.
- `path_provider` reste limité au code IO par import conditionnel et n'est jamais chargé dans le build Web.

## Vérification avant mise en production

```bash
flutter config --enable-web
flutter create --platforms=web .
flutter pub get
dart run sqflite_common_ffi_web:setup --force
flutter analyze
flutter test
flutter build web --release --base-href="/GesApp/"
```
