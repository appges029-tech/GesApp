# Android — APK installable

Un APK Android de type `release` doit être signé. Sans keystore, Gradle peut
compiler un fichier APK, mais Android refuse son installation avec le message
générique « Application non installée ». Le build release est donc maintenant
bloqué tant qu'une signature valide n'est pas configurée.

## Préparer la signature locale

Créer la keystore une seule fois et la conserver dans un emplacement privé et
sauvegardé. Ne jamais la commiter ni en changer entre deux mises à jour.

```bash
keytool -genkeypair -v \
  -keystore "$HOME/.gesapp/gesapp-release.jks" \
  -alias gesapp \
  -keyalg RSA -keysize 4096 -validity 10000
```

Copier ensuite `android/key.properties.example` vers
`android/key.properties`, puis remplacer ses valeurs. `storeFile` peut être un
chemin absolu, ou un chemin relatif au dossier `android`.

```properties
storePassword=mot-de-passe-de-la-keystore
keyPassword=mot-de-passe-de-la-cle
keyAlias=gesapp
storeFile=/chemin/prive/gesapp-release.jks
```

Générer et vérifier l'APK installable :

```bash
tool/preflight_release.sh
```

Le fichier à distribuer est
`build/app/outputs/flutter-apk/app-release.apk`. Le script exécute
`apksigner verify` : ne diffusez pas l'APK si cette vérification échoue.

## Mises à jour et erreur d'installation

Pour mettre à jour une installation existante, conserver **le même**
`applicationId` (`com.godfirst.gesapp`) et exactement la même keystore. Une
APK signée avec une autre clé ne peut pas remplacer l'application déjà présente
et Android peut également afficher « Application non installée ».

Pour un essai ponctuel avec une autre clé, désinstallez l'ancienne application
depuis le téléphone avant l'installation. Attention : cela efface les données
locales ; exportez une sauvegarde GesApp au préalable.

## Signature GitHub Actions

Les workflows Android requièrent les secrets suivants pour publier un APK
installable :

- `ANDROID_KEYSTORE_BASE64` : contenu Base64 de la keystore (`base64 -w 0
  /chemin/gesapp-release.jks` sous GNU/Linux) ;
- `ANDROID_KEYSTORE_PASSWORD` ;
- `ANDROID_KEY_ALIAS` ;
- `ANDROID_KEY_PASSWORD`.

Ils s'ajoutent aux secrets Supabase déjà demandés par les workflows. La
keystore décodée et `android/key.properties` restent des fichiers temporaires
ignorés par Git.
