Write-Host "Determine Artifacts"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$appsFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$apps = @(Copy-AppFilesToFolder -appFiles @("$env:apps".Split(',')) -folder $appsFolder)

$type = @("sandbox","onprem")[$env:artifactOnPrem -eq 'true']
$artifactVersion = $env:artifactVersion
$nugetServerUrl = $env:nugetServerUrl
$nugetToken = $env:nugetToken
$country = $env:country
$additionalCountries = @("$env:additionalCountries".Split(','))

# Determine BC artifacts needed for building missing runtime packages
# Find the highest application dependency for the apps in order to determine which BC Application version to use for runtime packages
$highestApplicationDependency = '1.0.0.0'

$allArtifacts = $false
$runtimeDependencyPackageIds = @{}
$artifactsNeeded = @()

foreach($appFile in $apps) {
    $appName = [System.IO.Path]::GetFileName($appFile)
    $appJson = Get-AppJsonFromAppFile -appFile $appFile

    # Determine Application Dependency for this app
    if ($appJson.PSObject.Properties.Name -eq "Application") {
        $applicationDependency = $appJson.application
    }
    else {
        $baseAppDependency = $appJson.dependencies | Where-Object { $_.Name -eq "Base Application" -and $_.Publisher -eq "Microsoft" }
        if ($baseAppDependency) {
            $applicationDependency = $baseAppDependency.Version
        }
        else {
            throw "Cannot determine application dependency for $appFile"
        }
    }

    # Determine highest application dependency for all apps
    if ([System.Version]$applicationDependency -gt [System.Version]$highestApplicationDependency) {
        $highestApplicationDependency = $applicationDependency
    }

    # Test whether a NuGet package exists for this app?
    $package = Get-BcNuGetPackage -nuGetServerUrl $nugetServerUrl -nuGetToken $nuGetToken -packageName $appJson.id -version $appJson.version -select Exact
    if ($package) {
        # Package exists determine runtime dependency package id
        $runTimeDependencyPackageId = GetRuntimeDependencyPackageId -package $package
        $runtimeDependencyPackageIds += @{ $appName = $runtimeDependencyPackageId }
    }
    else {
        # If just one of the apps doesn't exist as a nuget package, we need to create a new indirect nuget package and build all runtime versions of the nuget
        $package = Join-Path ([System.IO.Path]::GetTempPath()) ([GUID]::NewGuid().ToString())
        New-BcNuGetPackage -appfile $appFile -isIndirectPackage -runtimeDependencyId '{publisher}.{name}.runtime-{version}' -destinationFolder $package | Out-Null
        $runTimeDependencyPackageId = GetRuntimeDependencyPackageId -package $package
        $runtimeDependencyPackageIds += @{ $appName = $runTimeDependencyPackageId }
        $allArtifacts = $true
    }
}

# Determine which artifacts are needed for any of the apps
$artifactVersions = @()
$applicationVersion = [System.Version]$highestApplicationDependency
while ($true) {
    $artifacturl = Get-BCArtifactUrl -type $type -country $country -version "$applicationVersion" -select Closest
    if ($artifacturl) {
        $artifactVersions += @([System.Version]($artifacturl.split('/')[4]))
        $applicationVersion = [System.Version]"$($applicationVersion.Major).$($applicationVersion.Minor+1).0.0"
    }
    elseif ($applicationVersion.Minor -eq 0) {
        break
    }
    else {
        $applicationVersion = [System.Version]"$($applicationVersion.Major+1).0.0.0"
    }
}

if ($allArtifacts) {
    # all artifacts are needed
    $artifactsNeeded = $artifactVersions
}
else {
    # all indirect packages exists - determine which runtime package versions doesn't exist for the app
    # Look for latest artifacts first
    [Array]::Reverse($artifactVersions)
    # Search for runtime nuget packages for all apps
    foreach($appFile in $apps) {
        $appName = [System.IO.Path]::GetFileName($appFile)
        foreach($artifactVersion in $artifactVersions) {
            $runtimeDependencyPackageId = $runtimeDependencyPackageIds."$appName"    
            $package = Get-BcNuGetPackage -nuGetServerUrl $nugetServerUrl -nuGetToken $nuGetToken -packageName $runtimeDependencyPackageId -version "$artifactVersion" -select Exact
            if ($package) {
                break
            }
            else {
                $artifactsNeeded += @($artifactVersion)
            }
        }
    }
    $artifactsNeeded = @($artifactsNeeded | Select-Object -Unique)
}
Write-Host "Artifacts needed:"
$artifactsNeeded | ForEach-Object { Write-Host "- $_" }
Add-Content -Path $ENV:GITHUB_OUTPUT -Value "ArtifactsNeeded=$(ConvertTo-Json -InputObject @($artifactsNeeded | ForEach-Object { @{ "artifact" = "$_" } }) -Compress)" -Encoding UTF8

Write-Host "RuntimeDependencyPackageIds:"
$runtimeDependencyPackageIds | ForEach-Object { Write-Host "- $($_.Key) = $($_.Value)" }
Add-Content -Path $ENV:GITHUB_OUTPUT -Value "RuntimeDependencyPackageId=$(ConvertTo-Json -InputObject $runtimeDependencyPackageIds -Compress)" -Encoding UTF8
