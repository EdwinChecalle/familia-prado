param([string]$BaseUrl = 'http://localhost:8080')
$ErrorActionPreference='Stop'
Write-Host 'Familia Prado · Verificación API Bloque 02 (solo lectura)' -ForegroundColor Cyan
$email = Read-Host 'Correo de administrador'
$securePassword = Read-Host 'Contraseña de administrador' -AsSecureString
$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)
try { $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
try {
    $body = @{ email=$email;password=$password } | ConvertTo-Json
    $session = Invoke-RestMethod -Uri "$BaseUrl/api/auth/login" -Method POST -ContentType 'application/json' -Body $body
} finally { $password = $null; $body = $null }
$headers = @{ Authorization = "Bearer $($session.token)" }
$ping = Invoke-RestMethod "$BaseUrl/api/ping"
if ($ping.status -ne 'ok') { throw 'Falló /api/ping' }
Write-Host 'PASS API /ping'
$profile = Invoke-RestMethod "$BaseUrl/api/profile" -Headers $headers
if ([string]::IsNullOrWhiteSpace($profile.displayName)) { throw 'Falta displayName en /api/profile' }
Write-Host "PASS Cuenta: $($profile.displayName)"
$fund = Invoke-RestMethod "$BaseUrl/api/fund/summary" -Headers $headers
if ($null -eq $fund.available) { throw 'Falta summary.available' }
Write-Host 'PASS Caja, saldo disponible'
$expenses = @(Invoke-RestMethod "$BaseUrl/api/fund/expenses" -Headers $headers)
foreach($e in $expenses) {
    if (($e.PSObject.Properties.Name -notcontains 'registeredBy') -or [string]::IsNullOrWhiteSpace($e.registeredBy)) {
        throw 'No se identifica el registrador en un gasto'
    }
}
Write-Host 'PASS Gastos con autor de registro (si existen)'
$alerts = @(Invoke-RestMethod "$BaseUrl/api/alerts" -Headers $headers)
Write-Host "PASS Avisos personalizados: $($alerts.Count) encontrados"
$today = Get-Date -Format 'yyyy-MM-dd'
$weeks = @(Invoke-RestMethod "$BaseUrl/api/turns?from=$today&weeks=16" -Headers $headers)
if ($weeks.Count -ne 16) { throw "Se esperaban 16 semanas, se obtuvieron $($weeks.Count)" }
Write-Host 'PASS Calendario de 16 semanas por página'
Write-Host 'La sincronización SSE y el audio se validan manualmente con los dos emuladores.'
