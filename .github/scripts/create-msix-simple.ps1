#!/usr/bin/env powershell

# Simple MSIX creation script adapted for kiwix-build nightly workflow
param(
    [string]$BuildPath = "nightly-extracted",
    [string]$OutputPath = "$PWD\kiwix-desktop.msix",
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
$StagingDir = Join-Path $PWD "KiwixMSIXStaging"
if (Test-Path $StagingDir) {
    Remove-Item $StagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $StagingDir -Force | Out-Null

Write-Host "Created staging directory: $StagingDir" -ForegroundColor Yellow

try {
    # Copy all files from nightly build directly to staging directory
    Write-Host "Copying application files from nightly build..." -ForegroundColor Cyan

    # Copy files directly, preserving subdirectory structure but putting executables in root
    Get-ChildItem $BuildPath -Recurse | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
        # Get the relative path properly using Resolve-Path
        $fullBuildPath = (Resolve-Path $BuildPath).Path
        $relativePath = $_.FullName.Substring($fullBuildPath.Length + 1)

        # For files in subdirectories, preserve the structure
        # For files in root, put them in staging root
        if ($relativePath.Contains('\') -or $relativePath.Contains('/')) {
            # File is in a subdirectory - preserve structure
            $targetPath = Join-Path $StagingDir $relativePath
            $targetDir = Split-Path $targetPath
            if (-not (Test-Path $targetDir)) {
                New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
            }
        } else {
            # File is in root - copy to staging root
            $targetPath = Join-Path $StagingDir $_.Name
        }

        Copy-Item $_.FullName $targetPath -Force
        Write-Host "  Copied $relativePath" -ForegroundColor Gray
    }
    Write-Host "[OK] Application files copied" -ForegroundColor Green

    # List the complete contents of the staging directory for debugging
    Write-Host "=== STAGING DIRECTORY CONTENTS ===" -ForegroundColor Cyan
    Write-Host "Staging directory: $StagingDir" -ForegroundColor Gray

    Write-Host "Root files:" -ForegroundColor Yellow
    Get-ChildItem $StagingDir -File | ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor White
    }

    Write-Host "Subdirectories:" -ForegroundColor Yellow
    Get-ChildItem $StagingDir -Directory | ForEach-Object {
        Write-Host "  $($_.Name)/" -ForegroundColor Cyan
        # List files in each subdirectory
        Get-ChildItem $_.FullName -File | ForEach-Object {
            Write-Host "    $($_.Name)" -ForegroundColor Gray
        }
    }

    Write-Host "=== END STAGING CONTENTS ===" -ForegroundColor Cyan

    # Verify executable was copied correctly
    $stagedExePath = Join-Path $StagingDir "kiwix-desktop.exe"
    if (Test-Path $stagedExePath) {
        Write-Host "  Executable verified in staging: kiwix-desktop.exe" -ForegroundColor Green
    } else {
        Write-Host "[ERROR] kiwix-desktop.exe NOT found in staging root!" -ForegroundColor Red

        # Look for any .exe files
        Write-Host "Searching for .exe files in staging:" -ForegroundColor Yellow
        Get-ChildItem $StagingDir -Filter "*.exe" -Recurse | ForEach-Object {
            $relativePath = $_.FullName.Substring($StagingDir.Length + 1)
            Write-Host "  Found: $relativePath" -ForegroundColor Gray
        }
    }    # Create qt.conf for Qt configuration
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

    Write-Host "Copying MSIX assets..." -ForegroundColor Cyan

    $RequiredAssets = @(
        "Square150x150Logo.png",
        "Square44x44Logo.png",
        "StoreLogo.png",
        "Wide310x150Logo.png"
    )

    # Copy actual logo assets from project directory
    $SourceAssetsDir = "windows\msix\Assets"
    if (Test-Path $SourceAssetsDir) {
        foreach ($asset in $RequiredAssets) {
            $sourcePath = Join-Path $SourceAssetsDir $asset
            $assetPath = Join-Path $AssetsDir $asset

            if (Test-Path $sourcePath) {
                Copy-Item $sourcePath $assetPath -Force
                Write-Host "  Copied $asset" -ForegroundColor Green
            } else {
                Write-Host "  [WARNING] Asset not found: $asset - creating placeholder" -ForegroundColor Yellow
                # Create minimal placeholder PNG files (1x1 pixel transparent) as fallback
                $placeholderContent = [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
                [IO.File]::WriteAllBytes($assetPath, $placeholderContent)
            }
        }
    } else {
        Write-Host "  [WARNING] Source assets directory not found: $SourceAssetsDir" -ForegroundColor Yellow
        Write-Host "  Creating placeholder assets instead..." -ForegroundColor Yellow

        # Fallback to placeholders if assets directory doesn't exist
        $placeholderContent = [Convert]::FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")
        foreach ($asset in $RequiredAssets) {
            $assetPath = Join-Path $AssetsDir $asset
            [IO.File]::WriteAllBytes($assetPath, $placeholderContent)
            Write-Host "  Created placeholder $asset" -ForegroundColor Gray
        }
    }

    # Copy the manifest file
    $ManifestSource = Join-Path "windows" "msix" "Package.appxmanifest"
    $ManifestDest = Join-Path $StagingDir "AppxManifest.xml"

    if (-not (Test-Path $ManifestSource)) {
        Write-Host "[ERROR] Manifest template not found: $ManifestSource" -ForegroundColor Red
        exit 1
    }

    Copy-Item $ManifestSource $ManifestDest -Force

    # Replace version placeholder in manifest
    Write-Host "Processing manifest template..." -ForegroundColor Cyan
    $manifestContent = Get-Content $ManifestDest -Raw
    $manifestContent = $manifestContent -replace '\{VERSION\}', $Version
    Set-Content $ManifestDest $manifestContent -Encoding UTF8

    Write-Host "  Replaced {VERSION} with $Version" -ForegroundColor Gray

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
