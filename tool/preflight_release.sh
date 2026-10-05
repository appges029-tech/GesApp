#!/usr/bin/env bash
set -euo pipefail

if ! command -v flutter >/dev/null 2>&1; then
  echo "ERREUR: Flutter SDK introuvable dans PATH."
  exit 1
fi

if [[ ! -f android/key.properties ]]; then
  echo "ERREUR: android/key.properties est requis pour générer un APK installable."
  echo "Copiez android/key.properties.example puis renseignez votre keystore privée."
  exit 1
fi

echo "== GesApp RC preflight =="
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --release

APK="build/app/outputs/flutter-apk/app-release.apk"
if [[ ! -f "$APK" ]]; then
  echo "ERREUR: APK signé introuvable: $APK"
  echo "Configurez android/key.properties avec la keystore officielle."
  exit 1
fi

if ! command -v apksigner >/dev/null 2>&1; then
  echo "ERREUR: apksigner est requis pour vérifier la signature de l'APK."
  exit 1
fi

apksigner verify --verbose --print-certs "$APK"

echo ""
echo "VALIDATION TECHNIQUE OK"
echo "APK: $APK"
ls -lh "$APK"
