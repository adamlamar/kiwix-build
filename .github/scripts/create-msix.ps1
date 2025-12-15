#!/usr/bin/env powershell

# MSIX creation script adapted for kiwix-build CI workflow
param(
    [string]$BuildPath = "",
    [string]$OutputPath = "$PWD\kiwix-desktop.msix",
    [string]$Version = "2.4.1.0"
)

# Validate version format (must be four parts: major.minor.patch.build)
if ($Version -notmatch '^\d+\.\d+\.\d+\.\d+$') {
    Write-Host "[ERROR] Version must be in format major.minor.patch.build (e.g., 2.4.1.123)" -ForegroundColor Red
    Write-Host "Provided version: $Version" -ForegroundColor Gray
    exit 1
}

$ErrorActionPreference = "Stop"

Write-Host "Building Kiwix Desktop MSIX package..." -ForegroundColor Green
Write-Host "Version: $Version" -ForegroundColor Gray

# Auto-detect build path from kiwix-build structure
if ([string]::IsNullOrEmpty($BuildPath)) {
    $possiblePaths = @(
        "BUILD_win-amd64\INSTALL\bin",
        "BUILD_native_mixed\INSTALL\bin",
        "BUILD_windows\INSTALL\bin",
        "$env:HOME\BUILD_win-amd64\INSTALL\bin",
        "C:\Users\runneradmin\BUILD_win-amd64\INSTALL\bin"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $testExe = Join-Path $path "kiwix-desktop.exe"
            if (Test-Path $testExe) {
                $BuildPath = $path
                break
            }
        }
    }
}

Write-Host "Build Path: $BuildPath" -ForegroundColor Gray
Write-Host "Output Path: $OutputPath" -ForegroundColor Gray

# Validate inputs
if ([string]::IsNullOrEmpty($BuildPath) -or -not (Test-Path $BuildPath)) {
    Write-Host "[ERROR] Build path not found or not specified: $BuildPath" -ForegroundColor Red
    Write-Host "Available directories:" -ForegroundColor Yellow
    Get-ChildItem -Directory | Where-Object { $_.Name -like "*BUILD*" } | ForEach-Object {
        Write-Host "  $($_.FullName)" -ForegroundColor Gray
    }
    exit 1
}

$ExePath = Join-Path $BuildPath "kiwix-desktop.exe"
if (-not (Test-Path $ExePath)) {
    Write-Host "[ERROR] Executable not found: $ExePath" -ForegroundColor Red
    Write-Host "Contents of build directory:" -ForegroundColor Yellow
    Get-ChildItem $BuildPath | ForEach-Object {
        Write-Host "  $($_.Name)" -ForegroundColor Gray
    }
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
    # Copy application files from kiwix-build output
    Write-Host "Copying application files from kiwix-build output..." -ForegroundColor Cyan

    # Copy the main executable to staging root (required by MSIX)
    Copy-Item $ExePath $StagingDir -Force
    Write-Host "  Copied kiwix-desktop.exe" -ForegroundColor Green

    # Copy DLL dependencies from the bin directory
    $BinPath = $BuildPath
    Get-ChildItem $BinPath -Filter "*.dll" | ForEach-Object {
        Copy-Item $_.FullName $StagingDir -Force
        Write-Host "  Copied $($_.Name)" -ForegroundColor Gray
    }

    # Copy from lib directory if it exists
    $LibPath = $BuildPath -replace "\\bin$", "\lib"
    if (Test-Path $LibPath) {
        Write-Host "Copying additional libraries from: $LibPath" -ForegroundColor Cyan
        Get-ChildItem $LibPath -Filter "*.dll" -Recurse | ForEach-Object {
            $destPath = Join-Path $StagingDir $_.Name
            if (-not (Test-Path $destPath)) {
                Copy-Item $_.FullName $StagingDir -Force
                Write-Host "  Copied $($_.Name)" -ForegroundColor Gray
            } else {
                Write-Host "  Skipped $($_.Name) (already exists)" -ForegroundColor Yellow
            }
        }
    }

    # Look for Qt dependencies in various possible locations
    $QtPaths = @(
        "$env:Qt6_Dir\bin",
        "$env:QT_ROOT_DIR\bin",
        "C:\Qt\6.4.3\msvc2019_64\bin"
    )

    # Also check PATH for Qt directories
    $pathDirs = $env:PATH -split ';' | Where-Object { $_ -match '.*Qt.*bin' }
    $QtPaths += $pathDirs

    $QtFound = $false
    foreach ($qtPath in $QtPaths) {
        if ([string]::IsNullOrEmpty($qtPath)) { continue }
        if (Test-Path $qtPath) {
            Write-Host "Found Qt binaries at: $qtPath" -ForegroundColor Cyan

            # Copy ALL Qt DLLs instead of whitelisting specific ones
            Get-ChildItem $qtPath -Filter "*.dll" | ForEach-Object {
                $destPath = Join-Path $StagingDir $_.Name
                if (-not (Test-Path $destPath)) {
                    Copy-Item $_.FullName $StagingDir -Force
                    Write-Host "  Copied $($_.Name)" -ForegroundColor Gray
                } else {
                    Write-Host "  Skipped $($_.Name) (already exists)" -ForegroundColor Yellow
                }
            }

            # Copy Qt plugins
            $PluginsSource = Join-Path (Split-Path $qtPath) "plugins"
            if (Test-Path $PluginsSource) {
                $PluginsDest = Join-Path $StagingDir "plugins"
                Copy-Item $PluginsSource $PluginsDest -Recurse -Force
                Write-Host "  Copied Qt plugins directory" -ForegroundColor Gray
            }

            $QtFound = $true
            break
        }
    }

    if (-not $QtFound) {
        Write-Host "[WARNING] Qt binaries not found in standard locations" -ForegroundColor Yellow
        Write-Host "MSIX package may not work without Qt dependencies" -ForegroundColor Yellow
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
    }

    # Create qt.conf for Qt configuration
    Write-Host "Creating qt.conf..." -ForegroundColor Cyan
    $qtConf = "[Paths]`nPlugins = plugins`n`n[WebEngine]`nBrowserSubprocessPath = QtWebEngineProcess.exe"
    $qtConfPath = Join-Path $StagingDir "qt.conf"
    $qtConf | Set-Content $qtConfPath -Encoding UTF8

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
    if (-not (Test-Path $SourceAssetsDir)) {
        Write-Host "[ERROR] Source assets directory not found: $SourceAssetsDir" -ForegroundColor Red
        exit 1
    }

    foreach ($asset in $RequiredAssets) {
        $sourcePath = Join-Path $SourceAssetsDir $asset
        $assetPath = Join-Path $AssetsDir $asset

        if (Test-Path $sourcePath) {
            Copy-Item $sourcePath $assetPath -Force
            Write-Host "  Copied $asset" -ForegroundColor Green
        } else {
            Write-Host "[ERROR] Required asset not found: $asset" -ForegroundColor Red
            Write-Host "  Expected path: $sourcePath" -ForegroundColor Gray
            Write-Host "  Generate assets with: cd windows/msix/Assets; ./generate-logos.sh" -ForegroundColor Yellow
            exit 1
        }
    }

    # Copy the manifest file
    $ManifestSource = Join-Path (Join-Path "windows" "msix") "Package.appxmanifest"
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
        "/l"
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
