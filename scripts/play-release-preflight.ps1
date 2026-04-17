param(
    [string]$BuildName = "1.4.0",
    [int]$BuildNumber = 15,
    [switch]$SkipBuild
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
$androidRoot = Join-Path $projectRoot "android"
$appModuleRoot = Join-Path $androidRoot "app"
$keystorePropsPath = Join-Path $androidRoot "keystore.properties"

if (-not (Test-Path $keystorePropsPath)) {
    throw "Missing android/keystore.properties. Copy android/keystore.properties.example and fill it with real values."
}

$props = Parse-KeyValueFile -Path $keystorePropsPath
$requiredKeys = @("storeFile", "storePassword", "keyAlias", "keyPassword")

foreach ($requiredKey in $requiredKeys) {
    if (-not $props.ContainsKey($requiredKey) -or [string]::IsNullOrWhiteSpace($props[$requiredKey])) {
        throw "Missing required key '$requiredKey' in android/keystore.properties"
    }
}

if ($props["storePassword"] -eq "change-me" -or $props["keyPassword"] -eq "change-me") {
    throw "android/keystore.properties still contains placeholder passwords. Replace 'change-me' with real values."
}

$storeFileRelative = $props["storeFile"]
$storeFilePath = [System.IO.Path]::GetFullPath((Join-Path $appModuleRoot $storeFileRelative))

if (-not (Test-Path $storeFilePath)) {
    throw "Configured storeFile does not exist: $storeFilePath"
}

Push-Location $projectRoot
try {
    Write-Host "[1/4] flutter pub get"
    flutter pub get

    Write-Host "[2/4] flutter analyze"
    flutter analyze

    Write-Host "[3/4] flutter test"
    flutter test

    if ($SkipBuild) {
        Write-Host "[4/4] Build skipped by -SkipBuild."
    } else {
        Write-Host "[4/4] flutter build appbundle --release --build-name $BuildName --build-number $BuildNumber"
        flutter build appbundle --release --build-name $BuildName --build-number $BuildNumber
        Write-Host "AAB generated at: build/app/outputs/bundle/release/app-release.aab"
    }

    $artifactRoot = Export-CheckingReleaseArtifacts `
        -ProjectRoot $projectRoot `
        -BuildName $BuildName `
        -BuildNumber $BuildNumber
    Write-Host "Release artifacts archived at: $artifactRoot"
}
finally {
    Pop-Location
}
