#!/usr/bin/env powershell

# Download and extract nightly build
param(
    [string]$Url,
    [string]$ExtractPath = "nightly-extracted"
)

Write-Host "Downloading nightly build from: $Url" -ForegroundColor Yellow

$zipPath = "nightly-build.zip"

try {
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $Url -OutFile $zipPath -UseBasicParsing
    Write-Host "[OK] Download completed" -ForegroundColor Green

    # Verify download
    $size = (Get-Item $zipPath).Length
    Write-Host "Downloaded file size: $($size / 1MB) MB" -ForegroundColor Gray

    # Extract the archive
    Write-Host "Extracting nightly build..." -ForegroundColor Yellow
    Expand-Archive -Path $zipPath -DestinationPath $ExtractPath -Force

    # List contents to verify
    Write-Host "Extracted contents:" -ForegroundColor Cyan
    Get-ChildItem $ExtractPath -Recurse | Select-Object -First 10 | ForEach-Object { Write-Host "  $($_.Name)" }

    Write-Host "[OK] Nightly build ready for MSIX packaging" -ForegroundColor Green

} catch {
    Write-Error "Failed to download or extract nightly build: $($_.Exception.Message)"
    exit 1
}
