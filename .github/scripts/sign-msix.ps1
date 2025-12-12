#!/usr/bin/env powershell

# Sign MSIX package with certificate
param(
    [string]$MsixPath = "$env:TEMP\kiwix-desktop.msix",
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

# Sign the package
Write-Host "Signing MSIX package..." -ForegroundColor Cyan
Write-Host "Command: signtool sign /debug /fd SHA256 /f `"$CertificatePath`" /p [PASSWORD] /tr http://timestamp.digicert.com /td sha256 /v `"$MsixPath`"" -ForegroundColor Gray

$signResult = & $signToolPath sign /fd SHA256 /f $CertificatePath /p $env:SIGNING_PASSWORD /tr "http://timestamp.digicert.com" /td sha256 /v $MsixPath 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "[OK] MSIX package signed successfully!" -ForegroundColor Green
} else {
    Write-Host "[ERROR] Signing failed with exit code: $LASTEXITCODE" -ForegroundColor Red
    Write-Host "SignTool output:" -ForegroundColor Yellow
    $signResult | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }

    # Common troubleshooting info
    Write-Host "" -ForegroundColor Gray
    Write-Host "Common causes:" -ForegroundColor Yellow
    Write-Host "  1. Certificate format issues (ensure it's a valid .pfx file)" -ForegroundColor Gray
    Write-Host "  2. Incorrect password" -ForegroundColor Gray
    Write-Host "  3. Certificate doesn't have code signing capability" -ForegroundColor Gray
    Write-Host "  4. Timestamp server unavailable" -ForegroundColor Gray
    Write-Host "  5. MSIX file is corrupted or locked" -ForegroundColor Gray

    Remove-Item $CertificatePath -Force -ErrorAction SilentlyContinue
    exit 1
}

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
$finalPath = "$env:TEMP\kiwix-desktop-$timestamp.msix"
Move-Item $MsixPath $finalPath -Force
Write-Host "[OK] Final signed package: $finalPath" -ForegroundColor Green

# Set output for artifact upload
echo "SIGNED_MSIX_PATH=$finalPath" >> $env:GITHUB_ENV

Write-Host "Signing process completed successfully!" -ForegroundColor Green
exit 0
