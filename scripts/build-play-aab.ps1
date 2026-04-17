param(
    [string]$BuildName = "1.4.0",
    [int]$BuildNumber = 15
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "release-artifact-utils.ps1")

function Parse-KeyValueFile {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -Path $Path) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed.StartsWith("#")) { continue }

        $split = $trimmed -split "=", 2
        if ($split.Count -ne 2) { continue }

        $key = $split[0].Trim()
        $value = $split[1].Trim()
        $values[$key] = $value
    }
    return $values
}

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$keystorePropertiesPath = Join-Path $projectRoot "android\keystore.properties"
$appModuleRoot = Join-Path $projectRoot "android\app"

if (-not (Test-Path $keystorePropertiesPath)) {
    throw "Arquivo ausente: android/keystore.properties. Copie android/keystore.properties.example e preencha os dados reais do upload key."
}

$props = Parse-KeyValueFile -Path $keystorePropertiesPath
$requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")

foreach ($requiredKey in $requiredKeys) {
    if (-not $props.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($props[$requiredKey])) {
        throw "Propriedade obrigatoria ausente no android/keystore.properties: $requiredKey"
    }
}

if ($props["storePassword"] -eq "change-me" -or $props["keyPassword"] -eq "change-me") {
    throw "android/keystore.properties ainda contem placeholders ('change-me'). Substitua por valores reais."
}

$storeFilePath = [System.IO.Path]::GetFullPath((Join-Path $appModuleRoot $props["storeFile"]))
if (-not (Test-Path $storeFilePath)) {
    throw "Arquivo de keystore nao encontrado: $storeFilePath"
}

Push-Location $projectRoot
try {
    Write-Host "[1/4] flutter pub get"
    flutter pub get

    Write-Host "[2/4] flutter analyze"
    flutter analyze

    Write-Host "[3/4] flutter test"
    flutter test

    Write-Host "[4/4] flutter build appbundle --release --build-name $BuildName --build-number $BuildNumber"
    flutter build appbundle --release --build-name $BuildName --build-number $BuildNumber

    Write-Host "AAB gerado em: build/app/outputs/bundle/release/app-release.aab"
    $artifactRoot = Export-CheckingReleaseArtifacts `
        -ProjectRoot $projectRoot `
        -BuildName $BuildName `
        -BuildNumber $BuildNumber
    Write-Host "Artefatos de release arquivados em: $artifactRoot"
}
finally {
    Pop-Location
}
