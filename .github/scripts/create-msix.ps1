#!/usr/bin/env powershell

# Create MSIX package using MakeAppx
param(
    [string]$PackageDir = "KiwixDesktop_Package",
    [string]$OutputPath = "$env:TEMP\kiwix-desktop.msix"
)

Write-Host "Creating MSIX package..." -ForegroundColor Yellow

# Find MakeAppx tool
$makeAppxPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\makeappx.exe"
if (-not (Test-Path $makeAppxPath)) {
    $WindowsKitsPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    $makeAppxPath = Get-ChildItem -Path $WindowsKitsPath -Recurse -Filter "makeappx.exe" |
                   Where-Object { $_.Directory.Name -like "*x64*" } |
                   Sort-Object Name -Descending |
                   Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path $makeAppxPath)) {
    Write-Error "MakeAppx tool not found. Windows SDK is required."
    exit 1
}

Write-Host "Using MakeAppx: $makeAppxPath" -ForegroundColor Cyan
Write-Host "Package directory: $PackageDir" -ForegroundColor Cyan
Write-Host "Output MSIX: $OutputPath" -ForegroundColor Cyan

# Create the MSIX package
& $makeAppxPath pack /d $PackageDir /p $OutputPath /l /o

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create MSIX package (exit code: $LASTEXITCODE)"
    exit 1
}

if (Test-Path $OutputPath) {
    $size = (Get-Item $OutputPath).Length
    Write-Host "[OK] MSIX package created successfully" -ForegroundColor Green
    Write-Host "Package size: $([math]::Round($size / 1MB, 2)) MB" -ForegroundColor Gray
    Write-Host "Package location: $OutputPath" -ForegroundColor Gray
} else {
    Write-Error "MSIX package was not created"
    exit 1
}
