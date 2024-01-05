Write-Host "Generate Runtime NuGet Packages"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$appsFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$apps = @(Copy-AppFilesToFolder -appFiles @("$env:apps".Split(',')) -folder $appsFolder)

$nugetServerUrl = $env:nugetServerUrl
$nugetToken = $env:nugetToken

foreach($appFile in $apps) {
    $appJson = Get-AppJsonFromAppFile -appFile $appFile

    # Test whether a NuGet package exists for this app?
    $package = Get-BcNuGetPackage -nuGetServerUrl $nugetServerUrl -nuGetToken $nuGetToken -packageName $appJson.id -version $appJson.version -select Exact
    if (-not $package) {
        # If just one of the apps doesn't exist as a nuget package, we need to create a new indirect nuget package and build all runtime versions of the nuget
        $package = New-BcNuGetPackage -appfile $appFile
        Push-BcNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $package
    }
}
