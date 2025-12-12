#!/usr/bin/env powershell

# Prepare MSIX package structure
param(
    [string]$ExtractedPath = "nightly-extracted",
    [string]$PackageDir = "KiwixDesktop_Package"
)

Write-Host "Preparing MSIX package structure..." -ForegroundColor Yellow

# Create package directory
New-Item -ItemType Directory -Path $PackageDir -Force

# Copy nightly build contents to package directory
Write-Host "Copying application files..." -ForegroundColor Cyan

# Use robocopy for reliable directory copying
$robocopyResult = robocopy $ExtractedPath $PackageDir /E /NFL /NDL /NJH /NJS /nc /ns /np
if ($LASTEXITCODE -gt 7) {
    Write-Error "Failed to copy files from $ExtractedPath to $PackageDir"
    exit 1
}

Write-Host "✅ Application files copied successfully" -ForegroundColor Green

# Copy and prepare MSIX manifest from template
$templatePath = "templates\Package.appxmanifest"
$manifestPath = "$PackageDir\AppxManifest.xml"

if (-not (Test-Path $templatePath)) {
    Write-Error "Template manifest not found at: $templatePath"
    exit 1
}

# Read template and replace version placeholder
$manifestContent = Get-Content $templatePath -Raw
$version = "3.4.0.0"  # You can parameterize this later if needed
$manifestContent = $manifestContent -replace '\{VERSION\}', $version

# Save the processed manifest
Set-Content -Path $manifestPath -Value $manifestContent -Encoding UTF8
Write-Host "✅ Manifest created from template: $templatePath" -ForegroundColor Green

# Create Assets directory and placeholder icon files for the template's expected paths
if (-not (Test-Path "$PackageDir\Assets")) {
    New-Item -ItemType Directory -Path "$PackageDir\Assets" -Force
}

# Create minimal PNG placeholders for required icons (template uses Assets\ path)
$pngBytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0x99, 0x01, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82)

@("StoreLogo.png", "Square44x44Logo.png", "Square150x150Logo.png", "Wide310x150Logo.png") | ForEach-Object {
    $iconPath = "$PackageDir\Assets\$_"
    if (-not (Test-Path $iconPath)) {
        [System.IO.File]::WriteAllBytes($iconPath, $pngBytes)
    }
}

Write-Host "✅ MSIX package structure prepared" -ForegroundColor Green
