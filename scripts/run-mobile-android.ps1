$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (!(Get-Command flutter -ErrorAction SilentlyContinue)) { throw 'Instala Flutter y agrégalo al PATH.' }
Push-Location (Join-Path $root 'mobile')
try {
    if (!(Test-Path 'android/app/src/main/AndroidManifest.xml')) {
        flutter create --project-name familia_prado --platforms=android .
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo generar el proyecto Android.' }
    }
    flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'No se pudieron descargar las dependencias Flutter.' }
    flutter test
    if ($LASTEXITCODE -ne 0) { throw 'Fallaron las pruebas Flutter.' }
    flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
} finally { Pop-Location }
