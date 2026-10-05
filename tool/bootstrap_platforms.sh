#!/usr/bin/env bash
set -euo pipefail
if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK introuvable. Installez Flutter puis relancez ce script."
  exit 1
fi
flutter create --platforms=android,ios,windows,web,macos,linux --org org.godfirst --project-name gesapp .
flutter pub get
flutter analyze
flutter test
echo "Plateformes Flutter générées et projet vérifié."
