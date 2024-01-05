Write-Host "Generate Runtime NuGet Packages"

. (Join-Path $PSScriptRoot "HelperFunctions.ps1")

$env:runtimedependencyPackageIds | Out-Host

$appsFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$apps = @(CopyAppFilesToFolder -appFiles @("$env:apps".Split(',')) -folder $appsFolder)

$dependenciesFolder = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString())
$dependencies = @(CopyAppFilesToFolder -appFiles @("$env:dependencies".Split(',')) -folder $dependenciesFolder)

$type = @("sandbox","onprem")[$env:artifactOnPrem -eq 'true']
$artifactVersion = $env:artifactVersion
$nugetServerUrl = $env:nugetServerUrl
$nugetToken = $env:nugetToken
$country = $env:country
$additionalCountries = @("$env:additionalCountries".Split(','))
$runtimeDependencyPackageIds = $env:runtimedependencyPackageIds | ConvertFrom-Json

$artifacturl = Get-BCArtifactUrl -type $type -country $country -version $artifactVersion -select Closest
$global:runtimeAppFiles = @{}
$global:countrySpecificRuntimeAppFiles = @{}
Convert-BcAppsToRuntimePackages -containerName $containerName -artifactUrl $artifacturl -imageName '' -apps $apps -publishApps $dependencies -skipVerification -afterEachRuntimeCreation { Param($ht)
    if (-not $ht.runtimeFile) { throw "Could not generate runtime package" }
    $appName = [System.IO.Path]::GetFileName($ht.appFile)
    $global:runtimeAppFiles += @{ $appName = $ht.runtimeFile }
    $global:countrySpecificRuntimeAppFiles += @{ $appName = @{} }
}
foreach($ct in $additionalCountries) {
    $artifacturl = Get-BCArtifactUrl -type $type -country $ct -version $artifactVersion -select Closest
    Convert-BcAppsToRuntimePackages -containerName $containerName -artifactUrl $artifacturl -imageName '' -apps $apps -publishApps $dependencies -skipVerification -afterEachRuntimeCreation { Param($ht)
        if (-not $ht.runtimeFile) { throw "Could not generate runtime package" }
        $appName = [System.IO.Path]::GetFileName($ht.appFile)
        $global:countrySpecificRuntimeAppFiles."$appName" += @{ $ct = $ht.runtimeFile }
    }
}
$nextVersion = "$(([System.Version]$artifactVersion).Major).$(([System.Version]$artifactVersion).Minor+1)"

# For every app create and push nuget package
foreach($appFile in $apps) {
    $appName = [System.IO.Path]::GetFileName($appFile)
    $runtimeDependencyPackageId = $runtimeDependencyPackageIds."$appName"    
    $package = Get-BcNuGetPackage -nuGetServerUrl $nugetServerUrl -nuGetToken $nuGetToken -packageName $runtimeDependencyPackageId -version $artifactVersion -select Exact
    if ($package) {
        # Package already exists in that exact version
        continue
    }
    $runtimePackage = New-BcNuGetPackage -appfile $global:runtimeAppFiles."$appName" -countrySpecificAppFiles $global:countrySpecificRuntimeAppFiles."$appName" -packageId $runtimeDependencyPackageId -packageVersion $artifactVersion -applicationDependency "[$artifactVersion,$nextversion)"
    Push-BcNuGetPackage -nuGetServerUrl $nuGetServerUrl -nuGetToken $nuGetToken -bcNuGetPackage $runtimePackage
}
