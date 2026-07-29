param(
    [Parameter(Mandatory=$true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"
$fontRoot = Join-Path $env:WINDIR "Fonts"
$out = Join-Path $Destination "win10-ui-fonts"
New-Item -ItemType Directory -Force -Path $out | Out-Null

# Familles susceptibles d'intervenir dans l'interface Win32/dvaui. Les fichiers
# restent privés et ne doivent jamais être ajoutés au dépôt Git.
$files = @(
    "tahoma.ttf", "tahomabd.ttf",
    "segoeui.ttf", "segoeuib.ttf", "segoeuii.ttf", "segoeuiz.ttf",
    "segoeuil.ttf", "seguili.ttf",
    "seguisb.ttf", "seguisbi.ttf",
    "segoeuisl.ttf", "seguisli.ttf",
    "micross.ttf",
    "arial.ttf", "arialbd.ttf", "ariali.ttf", "arialbi.ttf",
    "verdana.ttf", "verdanab.ttf", "verdanai.ttf", "verdanaz.ttf"
)

$copied = @()
foreach ($name in $files) {
    $src = Join-Path $fontRoot $name
    if (Test-Path $src) {
        Copy-Item -Force $src (Join-Path $out $name)
        $copied += $name
    }
}

reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts" `
    (Join-Path $out "HKLM-Fonts.reg") /y | Out-Null
reg export "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\FontSubstitutes" `
    (Join-Path $out "HKLM-FontSubstitutes.reg") /y | Out-Null
reg export "HKCU\Control Panel\Desktop\WindowMetrics" `
    (Join-Path $out "HKCU-WindowMetrics.reg") /y | Out-Null

$manifest = foreach ($name in $copied) {
    $path = Join-Path $out $name
    $hash = Get-FileHash -Algorithm SHA256 $path
    [PSCustomObject]@{
        File = $name
        Bytes = (Get-Item $path).Length
        SHA256 = $hash.Hash.ToLower()
    }
}
$manifest | ConvertTo-Json | Set-Content -Encoding UTF8 `
    (Join-Path $out "manifest.json")

Get-ComputerInfo |
    Select-Object WindowsProductName, WindowsVersion, OsBuildNumber |
    ConvertTo-Json |
    Set-Content -Encoding UTF8 (Join-Path $out "windows-version.json")

Write-Host "Bundle privé créé dans $out"
Write-Host "Ne pas ajouter ces fichiers propriétaires à Git."

