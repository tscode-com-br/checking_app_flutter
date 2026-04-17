function Export-CheckingReleaseArtifacts {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        [string]$BuildName,

        [Parameter(Mandatory = $true)]
        [int]$BuildNumber
    )

    $bundleSourcePath = Join-Path $ProjectRoot "build\app\outputs\bundle\release\app-release.aab"
    $mappingSourceDirectory = Join-Path $ProjectRoot "build\app\outputs\mapping\release"
    $mappingSourcePath = Join-Path $mappingSourceDirectory "mapping.txt"

    if (-not (Test-Path $bundleSourcePath)) {
        throw "Release AAB not found: $bundleSourcePath"
    }

    if (-not (Test-Path $mappingSourcePath)) {
        throw "R8 mapping file not found: $mappingSourcePath"
    }

    $releaseId = "$BuildName+$BuildNumber"
    $artifactRoot = Join-Path $ProjectRoot "build\release-artifacts\$releaseId"
    $mappingDestinationDirectory = Join-Path $artifactRoot "r8-mapping"
    $bundleDestinationPath = Join-Path $artifactRoot "app-release.aab"
    $metadataPath = Join-Path $artifactRoot "release-metadata.json"

    if (Test-Path $artifactRoot) {
        Remove-Item -Path $artifactRoot -Recurse -Force
    }

    New-Item -ItemType Directory -Path $mappingDestinationDirectory -Force | Out-Null
    Copy-Item -Path $bundleSourcePath -Destination $bundleDestinationPath -Force
    Copy-Item -Path (Join-Path $mappingSourceDirectory "*") -Destination $mappingDestinationDirectory -Recurse -Force

    $metadata = [ordered]@{
        releaseId = $releaseId
        buildName = $BuildName
        buildNumber = $BuildNumber
        archivedAtUtc = (Get-Date).ToUniversalTime().ToString("o")
        archivedBundle = $bundleDestinationPath
        archivedMappingFile = Join-Path $mappingDestinationDirectory "mapping.txt"
        sourceBundle = $bundleSourcePath
        sourceMappingDirectory = $mappingSourceDirectory
    }

    $metadata |
        ConvertTo-Json -Depth 3 |
        Set-Content -Path $metadataPath -Encoding UTF8

    return $artifactRoot
}