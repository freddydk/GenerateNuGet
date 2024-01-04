$bcContainerHelperPath = 'https://github.com/freddydk/navcontainerhelper/archive/refs/heads/nuget.zip'

$tempName = Join-Path ([System.IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString())
Write-Host "Downloading BcContainerHelper developer version from $bcContainerHelperVersion"
$webclient = New-Object System.Net.WebClient
$webclient.DownloadFile($bcContainerHelperVersion, "$tempName.zip")
Expand-Archive -Path "$tempName.zip" -DestinationPath "$tempName"
Remove-Item "$tempName.zip"
$bcContainerHelperPath = (Get-Item -Path (Join-Path $tempName "*\BcContainerHelper.ps1")).FullName
. $bcContainerHelperPath
$helperFunctionsPath = (Get-Item -Path (Join-Path $tempName "*\HelperFunctions.ps1")).FullName
. $helperFunctionsPath

$isPsCore = $PSVersionTable.PSVersion -ge "6.0.0"
if ($isPsCore) {
    $byteEncodingParam = @{ "asByteStream" = $true }
    $allowUnencryptedAuthenticationParam = @{ "allowUnencryptedAuthentication" = $true }
}
else {
    $byteEncodingParam = @{ "Encoding" = "byte" }
    $allowUnencryptedAuthenticationParam = @{ }
    $isWindows = $true
    $isLinux = $false
    $IsMacOS = $false
}

function GetRuntimeDependencyPackageId {
    Param(
        [string] $package
    )
    $nuspecFile = Join-Path $package 'manifest.nuspec'
    $nuspec = [xml](Get-Content -Path $nuspecFile -Encoding UTF8)
    $packageId = $nuspec.package.metadata.id
    if ($packageId -match "^(.*).$($appJson.id)`$") {
        $publisherAndName = $Matches[1]
    }
    else {
        throw "Cannot determine publisher and name from the $packageId"
    }
    $runtimeDependencyPackageId = $nuspec.package.metadata.dependencies.dependency | Where-Object { $_.id -like "$($publisherAndName).runtime-*" } | Select-Object -ExpandProperty id
    if (-not $runtimeDependencyPackageId) {
        throw "Cannot determine dependency package id"
    }
    return $runtimeDependencyPackageId
}

$ErrorActionPreference = "stop"
