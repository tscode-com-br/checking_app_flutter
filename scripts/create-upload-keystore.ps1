param(
    [string]$KeystorePath = "android/keys/checking-upload-keystore.jks",
    [string]$Alias = "checking-upload",
    [int]$ValidityDays = 10000
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$fullKeystorePath = Join-Path $projectRoot $KeystorePath
$keystoreDir = Split-Path -Parent $fullKeystorePath

if (Test-Path $fullKeystorePath) {
    throw "Keystore already exists: $fullKeystorePath"
}

$keytool = Get-Command keytool -ErrorAction SilentlyContinue
if (-not $keytool) {
    throw "Command 'keytool' not found. Install a JDK (Java 17+) and ensure keytool is in PATH."
}

if (-not (Test-Path $keystoreDir)) {
    New-Item -ItemType Directory -Path $keystoreDir -Force | Out-Null
}

Write-Host "Generating upload keystore at: $fullKeystorePath"
& $keytool.Path `
    -genkeypair `
    -v `
    -storetype JKS `
    -keyalg RSA `
    -keysize 2048 `
    -validity $ValidityDays `
    -alias $Alias `
    -keystore $fullKeystorePath

if (-not (Test-Path $fullKeystorePath)) {
    throw "Keystore generation failed. File was not created: $fullKeystorePath"
}

Write-Host "Keystore generated successfully."
Write-Host "Next steps:"
Write-Host "1) Copy android/keystore.properties.example to android/keystore.properties"
Write-Host "2) Replace storePassword and keyPassword with real values"
Write-Host "3) Run: pwsh ./scripts/play-release-preflight.ps1"
