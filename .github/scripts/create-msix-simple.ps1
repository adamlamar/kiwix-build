#!/usr/bin/env powershell

# Simple MSIX creation script adapted for kiwix-build nightly workflow
param(
    [string]$BuildPath = "KiwixDesktop_Package",
    [string]$OutputPath = "$env:TEMP\kiwix-desktop.msix",
    [string]$Version = "2.4.1.0"
)

$ErrorActionPreference = "Stop"

Write-Host "Building Kiwix Desktop MSIX package..." -ForegroundColor Green
Write-Host "Build Path: $BuildPath" -ForegroundColor Gray
Write-Host "Output Path: $OutputPath" -ForegroundColor Gray
Write-Host "Version: $Version" -ForegroundColor Gray

# Validate inputs
if (-not (Test-Path $BuildPath)) {
    Write-Host "[ERROR] Build path not found: $BuildPath" -ForegroundColor Red
    exit 1
}

$ExePath = Join-Path $BuildPath "kiwix-desktop.exe"
if (-not (Test-Path $ExePath)) {
    Write-Host "[ERROR] Executable not found: $ExePath" -ForegroundColor Red
    exit 1
}

# Create staging directory
$StagingDir = Join-Path $env:TEMP "KiwixMSIXStaging"
if (Test-Path $StagingDir) {
    Remove-Item $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

Write-Host "Created staging directory: $StagingDir" -ForegroundColor Yellow

try {
    # Copy all files from nightly build to staging directory
    Write-Host "Copying application files..." -ForegroundColor Cyan

    Get-ChildItem $BuildPath -Recurse | ForEach-Object {
        $relativePath = $_.FullName.Substring($BuildPath.Length + 1)
        $targetPath = Join-Path $StagingDir $relativePath

        if ($_.PSIsContainer) {
            # It's a directory
            if (-not (Test-Path $targetPath)) {
                New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
            }
        } else {
            # It's a file
            $targetDir = Split-Path $targetPath
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
            Copy-Item $_.FullName $targetPath -Force
            Write-Host "  Copied $relativePath" -ForegroundColor Gray
        }
    }

    Write-Host "[OK] Application files copied" -ForegroundColor Green

    # Create qt.conf for Qt configuration
    Write-Host "Creating qt.conf..." -ForegroundColor Cyan
    $qtConf = @"
[Paths]
Plugins = plugins

[WebEngine]
BrowserSubprocessPath = QtWebEngineProcess.exe
"@
    $qtConf | Set-Content "$StagingDir\qt.conf" -Encoding UTF8

    # Create Assets directory for MSIX icons
    $AssetsDir = Join-Path $StagingDir "Assets"
    New-Item -ItemType Directory -Path $AssetsDir -Force | Out-Null

    Write-Host "Creating MSIX assets..." -ForegroundColor Cyan

    $RequiredAssets = @(
        "Square150x150Logo.png",
        "Square44x44Logo.png",
        "StoreLogo.png"
    )

    # Create minimal placeholder PNG files (1x1 pixel transparent)
    $placeholderContent = [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
    foreach ($asset in $RequiredAssets) {
        $assetPath = Join-Path $AssetsDir $asset
        [IO.File]::WriteAllBytes($assetPath, $placeholderContent)
        Write-Host "  Created placeholder $asset" -ForegroundColor Gray
    }

    # Copy the manifest file
    $ManifestSource = Join-Path "templates" "Package.appxmanifest"
    $ManifestDest = Join-Path $StagingDir "AppxManifest.xml"

    if (-not (Test-Path $ManifestSource)) {
        Write-Host "[ERROR] Manifest template not found: $ManifestSource" -ForegroundColor Red
        exit 1
    }

    Copy-Item $ManifestSource $ManifestDest -Force

    # Update version in manifest if different from default
    if ($Version -ne "2.4.1.0") {
        $manifestContent = Get-Content $ManifestDest -Raw
        $manifestContent = $manifestContent -replace 'Version="2\.4\.1\.0"', "Version=`"$Version`""
        Set-Content $ManifestDest $manifestContent -Encoding UTF8
    }

    Write-Host "[OK] Manifest processed" -ForegroundColor Green

    # Create the MSIX package
    Write-Host "Creating MSIX package..." -ForegroundColor Cyan

    # Ensure output directory exists
    $OutputDir = Split-Path $OutputPath
    if (-not (Test-Path $OutputDir)) {
        New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
    }

    # Find MakeAppx.exe
    $MakeAppxPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\makeappx.exe"
    if (-not (Test-Path $MakeAppxPath)) {
        # Try to find MakeAppx.exe in Windows SDK
        $WindowsKitsPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
        if (Test-Path $WindowsKitsPath) {
            $MakeAppxPath = Get-ChildItem -Path $WindowsKitsPath -Recurse -Filter "makeappx.exe" |
                           Where-Object { $_.Directory.Name -like "*x64*" } |
                           Sort-Object Name -Descending |
                           Select-Object -First 1 -ExpandProperty FullName
        }
    }

    if (-not $MakeAppxPath -or -not (Test-Path $MakeAppxPath)) {
        Write-Host "[ERROR] MakeAppx.exe not found. Windows SDK is required." -ForegroundColor Red
        exit 1
    }

    Write-Host "Using MakeAppx: $MakeAppxPath" -ForegroundColor Gray

    # Create the MSIX package
    $MakeAppxArgs = @(
        "pack",
        "/d", $StagingDir,
        "/p", $OutputPath,
        "/l"  # Enable file logging
    )

    Write-Host "Running: $MakeAppxPath $($MakeAppxArgs -join ' ')" -ForegroundColor Gray
    & $MakeAppxPath $MakeAppxArgs

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] MakeAppx failed with exit code: $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }

    Write-Host "[OK] MSIX package created successfully" -ForegroundColor Green

    # Display package information
    if (Test-Path $OutputPath) {
        $FileInfo = Get-Item $OutputPath
        Write-Host "Package size: $([math]::Round($FileInfo.Length / 1MB, 2)) MB" -ForegroundColor Cyan
        Write-Host "Package location: $OutputPath" -ForegroundColor Cyan
    }

} finally {
    # Cleanup staging directory
    if (Test-Path $StagingDir) {
        Remove-Item $StagingDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "Cleaned up staging directory" -ForegroundColor Yellow
    }
}

Write-Host "MSIX creation completed successfully!" -ForegroundColor Green
exit 0
