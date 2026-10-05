$ErrorActionPreference = 'Stop'

if (-not (Test-Path 'android/key.properties')) {
  throw 'android/key.properties est requis pour générer un APK installable. Copiez android/key.properties.example puis renseignez votre keystore privée.'
}

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  throw 'Flutter SDK introuvable dans PATH.'
}

Write-Host '== GesApp RC preflight =='
flutter --version
flutter doctor -v
flutter pub get
flutter analyze
flutter test
flutter build apk --release

$apk = 'build/app/outputs/flutter-apk/app-release.apk'
if (-not (Test-Path $apk)) {
    throw "APK signé introuvable: $apk. Configurez android/key.properties avec la keystore officielle."
}

$apksigner = Get-Command apksigner -ErrorAction SilentlyContinue
if (-not $apksigner) {
  throw 'apksigner est requis pour vérifier la signature de l''APK.'
}

& $apksigner.Source verify --verbose --print-certs $apk
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host ''
Write-Host 'VALIDATION TECHNIQUE OK'
Write-Host "APK: $apk"
Get-Item $apk | Format-List Name,Length,LastWriteTime
