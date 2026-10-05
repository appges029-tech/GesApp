$ErrorActionPreference = 'Stop'
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK introuvable. Installez Flutter puis relancez ce script.'
}
flutter create --platforms=android,ios,windows,web,macos,linux --org org.godfirst --project-name gesapp .
flutter pub get
flutter analyze
flutter test
Write-Host 'Plateformes Flutter générées et projet vérifié.'
