$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$path = Join-Path $root '.env'
if (!(Test-Path $path)) { throw 'Falta .env: copia .env.example, actualiza las claves y vuelve a ejecutar.' }
foreach ($line in Get-Content $path) {
    if ($line -match '^\s*([^#=\s]+)=(.*)$') {
        [System.Environment]::SetEnvironmentVariable($matches[1], $matches[2].Trim(), 'Process')
    }
}
if ($env:POSTGRES_PASSWORD -like 'CAMBIAR_*' -or $env:BOOTSTRAP_ADMIN_PASSWORD -like 'CAMBIAR_*') {
    throw 'Cambia las contraseñas de ejemplo en .env antes de ejecutar.'
}
$env:DB_URL = "jdbc:postgresql://localhost:5433/$env:POSTGRES_DB"
$env:DB_USER = $env:POSTGRES_USER
$env:DB_PASSWORD = $env:POSTGRES_PASSWORD
if (!(Get-Command mvn -ErrorAction SilentlyContinue)) { throw 'Instala Apache Maven 3.9+.' }
mvn -f (Join-Path $root 'backend/pom.xml') spring-boot:run
