#!/usr/bin/env powershell

# Validate and inspect signing certificate
param()

if (-not $env:SIGNING_CERTIFICATE -or -not $env:SIGNING_PASSWORD) {
    Write-Host "[ERROR] MSIX signing requires a certificate!" -ForegroundColor Red
    Write-Host ""
    Write-Host "To fix this, add these secrets to your GitHub repository:" -ForegroundColor Yellow
    Write-Host "  SIGNING_CERTIFICATE - Base64 encoded .pfx certificate file" -ForegroundColor Gray
    Write-Host "  SIGNING_PASSWORD - Certificate password" -ForegroundColor Gray
    Write-Error "Missing required signing certificate secrets"
    exit 1
}

Write-Host "[OK] Signing certificate secrets are available" -ForegroundColor Green

# Create temporary certificate file to inspect
try {
    $certBytes = [Convert]::FromBase64String($env:SIGNING_CERTIFICATE)
    $tempCertPath = "temp-cert.pfx"
    [IO.File]::WriteAllBytes($tempCertPath, $certBytes)

    Write-Host ""
    Write-Host "[INFO] Certificate Information:" -ForegroundColor Cyan
    Write-Host ("=" * 60) -ForegroundColor Gray

    # Load certificate and display information
    $cert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($tempCertPath, $env:SIGNING_PASSWORD)

    Write-Host "Subject: $($cert.Subject)" -ForegroundColor White
    Write-Host "Issuer: $($cert.Issuer)" -ForegroundColor White
    Write-Host "Serial Number: $($cert.SerialNumber)" -ForegroundColor White
    Write-Host "Thumbprint: $($cert.Thumbprint)" -ForegroundColor White
    Write-Host "Algorithm: $($cert.SignatureAlgorithm.FriendlyName)" -ForegroundColor White
    Write-Host "Key Size: $($cert.PublicKey.Key.KeySize) bits" -ForegroundColor White
    Write-Host "Valid From: $($cert.NotBefore.ToString('yyyy-MM-dd HH:mm:ss UTC'))" -ForegroundColor White
    Write-Host "Valid To: $($cert.NotAfter.ToString('yyyy-MM-dd HH:mm:ss UTC'))" -ForegroundColor White

    # Check certificate validity
    $now = Get-Date
    $daysUntilExpiry = ($cert.NotAfter - $now).Days
    if ($cert.NotAfter -lt $now) {
        Write-Host "[WARNING] Certificate EXPIRED $(-$daysUntilExpiry) days ago!" -ForegroundColor Red
    } elseif ($daysUntilExpiry -lt 30) {
        Write-Host "[WARNING] Certificate expires in $daysUntilExpiry days" -ForegroundColor Yellow
    } else {
        Write-Host "[OK] Certificate expires in $daysUntilExpiry days" -ForegroundColor Green
    }

    # Check enhanced key usage
    $hasCodeSigning = $false
    $ekuOids = @()
    foreach ($extension in $cert.Extensions) {
        if ($extension.Oid.Value -eq "2.5.29.37") {  # Enhanced Key Usage OID
            $eku = [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]$extension
            foreach ($usage in $eku.EnhancedKeyUsages) {
                $ekuOids += $usage.Value
                if ($usage.Value -eq "1.3.6.1.5.5.7.3.3") {  # Code Signing OID
                    $hasCodeSigning = $true
                }
            }
        }
    }

    Write-Host "Enhanced Key Usage OIDs: $($ekuOids -join ', ')" -ForegroundColor White

    if ($hasCodeSigning) {
        Write-Host "[OK] Certificate has Code Signing capability" -ForegroundColor Green
    } else {
        Write-Host "[WARNING] Certificate may not have Code Signing capability" -ForegroundColor Yellow
    }

    # Check if it's self-signed
    if ($cert.Subject -eq $cert.Issuer) {
        Write-Host "[INFO] Self-signed certificate" -ForegroundColor Yellow
    } else {
        Write-Host "[INFO] CA-issued certificate" -ForegroundColor Green
    }

    Write-Host ("=" * 60) -ForegroundColor Gray

    # Clean up temporary file
    Remove-Item $tempCertPath -Force -ErrorAction SilentlyContinue

} catch {
    Write-Host "[WARNING] Could not inspect certificate: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "This may indicate certificate format issues" -ForegroundColor Gray
}

# Ensure successful exit
exit 0
