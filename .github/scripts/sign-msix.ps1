#!/usr/bin/env powershell

# Sign MSIX package with certificate
param(
    [string]$MsixPath = "$PWD\kiwix-desktop.msix",
    [string]$CertificatePath = "signing-cert.pfx"
)

Write-Host "Starting MSIX signing process..." -ForegroundColor Yellow
Write-Host "MSIX Path: $MsixPath" -ForegroundColor Gray
Write-Host "Certificate Path: $CertificatePath" -ForegroundColor Gray

# Validate inputs
if (-not $env:SIGNING_CERTIFICATE -or -not $env:SIGNING_PASSWORD) {
    Write-Host "[ERROR] Missing required environment variables:" -ForegroundColor Red
    Write-Host "  SIGNING_CERTIFICATE - Base64 encoded certificate" -ForegroundColor Gray
    Write-Host "  SIGNING_PASSWORD - Certificate password" -ForegroundColor Gray
    exit 1
}

if (-not (Test-Path $MsixPath)) {
    Write-Host "[ERROR] MSIX package not found: $MsixPath" -ForegroundColor Red
    exit 1
}

# Create certificate file from base64
try {
    Write-Host "Creating certificate file from base64 data..." -ForegroundColor Cyan
    $certBytes = [Convert]::FromBase64String($env:SIGNING_CERTIFICATE)
    [IO.File]::WriteAllBytes($CertificatePath, $certBytes)
    Write-Host "[OK] Certificate file created: $CertificatePath" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to create certificate file: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

# Find SignTool
$signToolPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\signtool.exe"
if (-not (Test-Path $signToolPath)) {
    Write-Host "SignTool not found at expected location, searching..." -ForegroundColor Yellow
    $WindowsKitsPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
    if (Test-Path $WindowsKitsPath) {
        $signToolPath = Get-ChildItem -Path $WindowsKitsPath -Recurse -Filter "signtool.exe" |
                       Where-Object { $_.Directory.Name -like "*x64*" } |
                       Sort-Object Name -Descending |
                       Select-Object -First 1 -ExpandProperty FullName
    }
}

if (-not (Test-Path $signToolPath)) {
    Write-Host "[ERROR] SignTool not found. Windows SDK is required." -ForegroundColor Red
    Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "[OK] Using SignTool: $signToolPath" -ForegroundColor Green

# Test certificate before signing
Write-Host "Testing certificate..." -ForegroundColor Cyan
try {
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($CertificatePath, $env:SIGNING_PASSWORD)
    Write-Host "[OK] Certificate loaded successfully" -ForegroundColor Green
    Write-Host "  Subject: $($cert.Subject)" -ForegroundColor Gray
    Write-Host "  Expires: $($cert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray
    $cert.Dispose()
} catch {
    Write-Host "[ERROR] Certificate test failed: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue
    exit 1
}

# Validate MSIX package before signing
Write-Host "Validating MSIX package..." -ForegroundColor Cyan
try {
    # Check if it's a valid ZIP file (MSIX is ZIP-based)
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($MsixPath)
    $manifestFile = $archive.Entries | Where-Object { $_.Name -eq "AppxManifest.xml" }
    if (-not $manifestFile) {
        Write-Host "[ERROR] MSIX package is missing AppxManifest.xml" -ForegroundColor Red
        $archive.Dispose()
        Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue
        exit 1
    }
    $archive.Dispose()
    Write-Host "[OK] MSIX package structure is valid" -ForegroundColor Green
} catch {
    Write-Host "[ERROR] MSIX package validation failed: $($_.Exception.Message)" -ForegroundColor Red
    Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue
    exit 1
}

# Get MSIX file info
$msixInfo = Get-Item $MsixPath
Write-Host "MSIX file size: $($msixInfo.Length) bytes ($([math]::Round($msixInfo.Length / 1MB, 2)) MB)" -ForegroundColor Gray

# Sign the package
Write-Host "Signing MSIX package..." -ForegroundColor Cyan
# Sign the package
Write-Host "Signing MSIX package..." -ForegroundColor Cyan

# First try: Sign with timestamp
Write-Host "Attempt 1: Signing with timestamp..." -ForegroundColor Gray
Write-Host "Command: signtool sign /fd SHA256 /f `"$CertificatePath`" /p [PASSWORD] /tr http://timestamp.digicert.com /td sha256 /v `"$MsixPath`"" -ForegroundColor Gray

$signResult = & $signToolPath sign /debug /fd SHA256 /f $CertificatePath /p $env:SIGNING_PASSWORD /tr "http://timestamp.digicert.com" /td sha256 /v $MsixPath 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] MSIX package signed successfully with timestamp!" -ForegroundColor Green
    $signedSuccessfully = $true
} else {
    Write-Host "[WARNING] Signing with timestamp failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
    Write-Host "SignTool output:" -ForegroundColor Gray
    $signResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    # Second try: Sign without timestamp
    Write-Host ""
    Write-Host "Attempt 2: Signing without timestamp..." -ForegroundColor Gray
    Write-Host "Command: signtool sign /fd SHA256 /f `"$CertificatePath`" /p [PASSWORD] /v `"$MsixPath`"" -ForegroundColor Gray

    $signResult2 = & $signToolPath sign /fd SHA256 /f $CertificatePath /p $env:SIGNING_PASSWORD /v $MsixPath 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] MSIX package signed successfully without timestamp!" -ForegroundColor Green
        $signedSuccessfully = $true
    } else {
        Write-Host "[ERROR] Both signing attempts failed!" -ForegroundColor Red
        Write-Host "Second attempt output:" -ForegroundColor Yellow
        $signResult2 | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

        # Specific error analysis
        if ($signResult -match "0x8007000b" -or $signResult2 -match "0x8007000b") {
            Write-Host ""
            Write-Host "ERROR 0x8007000b (ERROR_BAD_FORMAT) detected:" -ForegroundColor Red
            Write-Host "This typically indicates:" -ForegroundColor Yellow
            Write-Host "  1. The MSIX file is corrupted or malformed" -ForegroundColor Gray
            Write-Host "  2. The MSIX was not created properly by MakeAppx" -ForegroundColor Gray
            Write-Host "  3. File permissions or access issues" -ForegroundColor Gray
            Write-Host "  4. The certificate store has issues" -ForegroundColor Gray
        }

        Write-Host ""
        Write-Host "Troubleshooting steps:" -ForegroundColor Yellow
        Write-Host "  1. Verify MSIX creation process completed successfully" -ForegroundColor Gray
        Write-Host "  2. Check if MSIX file is accessible and not locked" -ForegroundColor Gray
        Write-Host "  3. Try recreating the MSIX package" -ForegroundColor Gray
        Write-Host "  4. Verify certificate has proper Enhanced Key Usage" -ForegroundColor Gray

        Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue
        exit 1
    }
}

if ($signedSuccessfully) {
    # Verify the signature
    Write-Host "Verifying package signature..." -ForegroundColor Cyan
    $verifyResult = & $signToolPath verify /pa /v $MsixPath 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] Package signature verified successfully" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Signature verification failed (may be expected for self-signed certificates)" -ForegroundColor Yellow
        Write-Host "Verification output:" -ForegroundColor Gray
        $verifyResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
        Write-Host "This doesn't prevent the package from working in development scenarios" -ForegroundColor Gray
    }

    # Clean up certificate file
    Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue

    # Create final package with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
    $finalPath = "$PWD\kiwix-desktop-$timestamp.msix"
    Move-Item $MsixPath $finalPath -Force
    Write-Host "[OK] Final signed package: $finalPath" -ForegroundColor Green

    # Set output for artifact upload
    echo "SIGNED_MSIX_PATH=$finalPath" >> $env:GITHUB_ENV

    Write-Host "Signing process completed successfully!" -ForegroundColor Green
    exit 0
}
