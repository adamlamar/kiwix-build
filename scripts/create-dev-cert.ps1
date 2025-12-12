# PowerShell script to create a self-signed certificate for MSIX development and testing
param(
    [string]$CertificateName = "Kiwix Development",
    [string]$Publisher = "CN=Kiwix",
    [string]$OutputPath = "kiwix-dev-cert.pfx",
    [string]$Password = "password123"
)

$ErrorActionPreference = "Stop"

Write-Host "Creating development certificate for MSIX testing..." -ForegroundColor Green
Write-Host "Certificate Name: $CertificateName" -ForegroundColor Cyan
Write-Host "Publisher: $Publisher" -ForegroundColor Cyan
Write-Host "Output Path: $OutputPath" -ForegroundColor Cyan

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "If not running as Admin, follow the instructions to import the certificate manually at the end."
}

try {
    # Create self-signed certificate
    Write-Host "Creating self-signed certificate..." -ForegroundColor Yellow
    $cert = New-SelfSignedCertificate -Type CodeSigningCert -Subject $Publisher -KeyUsage DigitalSignature -FriendlyName $CertificateName -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

    # Export certificate to PFX file
    Write-Host "Exporting certificate to PFX file..." -ForegroundColor Yellow
    $securePwd = ConvertTo-SecureString -String $Password -Force -AsPlainText
    $fullOutputPath = Join-Path $PWD $OutputPath
    Export-PfxCertificate -Cert $cert -FilePath $fullOutputPath -Password $securePwd | Out-Null

    # Export public certificate for installation
    $cerPath = $fullOutputPath -replace "\.pfx$", ".cer"
    Export-Certificate -Cert $cert -FilePath $cerPath | Out-Null

    Write-Host "Certificate created successfully!" -ForegroundColor Green
    Write-Host "  PFX file: $fullOutputPath (password: $Password)" -ForegroundColor Cyan
    Write-Host "  CER file: $cerPath" -ForegroundColor Cyan

    # Add certificate to trusted root
    if ($isAdmin) {
        Write-Host "Installing certificate to Trusted Root..." -ForegroundColor Yellow
        try {
            Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\LocalMachine\Root" | Out-Null
            Write-Host "Certificate installed to Trusted Root store" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to install to Trusted Root: $($_.Exception.Message)"
        }

        # Also add to Trusted People
        try {
            Import-Certificate -FilePath $cerPath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople" | Out-Null
            Write-Host "Certificate installed to Trusted People store" -ForegroundColor Green
        } catch {
            Write-Warning "Failed to install to Trusted People: $($_.Exception.Message)"
        }
    } else {
        Write-Host ""
        Write-Host "To install the certificate for testing:" -ForegroundColor Yellow
        Write-Host "  1. Run PowerShell as Administrator" -ForegroundColor White
        Write-Host "  2. Import-Certificate -FilePath '$cerPath' -CertStoreLocation 'Cert:\LocalMachine\Root'" -ForegroundColor Gray
        Write-Host "  3. Import-Certificate -FilePath '$cerPath' -CertStoreLocation 'Cert:\LocalMachine\TrustedPeople'" -ForegroundColor Gray
    }

    Write-Host ""
    Write-Host "Next steps:" -ForegroundColor Cyan
    Write-Host "  1. Use this certificate to sign your MSIX package:" -ForegroundColor White
    Write-Host "     signtool sign /fd SHA256 /f `"$fullOutputPath`" /p `"$Password`" your-package.msix" -ForegroundColor Gray
    Write-Host "  2. Or add to GitHub secrets for CI/CD:" -ForegroundColor White
    Write-Host "     SIGNING_CERTIFICATE: $(([Convert]::ToBase64String([IO.File]::ReadAllBytes($fullOutputPath))))" -ForegroundColor Gray
    Write-Host "     SIGNING_PASSWORD: $Password" -ForegroundColor Gray

} catch {
    Write-Error "Failed to create certificate: $($_.Exception.Message)"
    exit 1
}

Write-Host ""
Write-Host "IMPORTANT NOTES:" -ForegroundColor Yellow
Write-Host "  This is a DEVELOPMENT certificate only" -ForegroundColor White
Write-Host "  Do NOT use for production or distribution" -ForegroundColor White
Write-Host "  This certificate is not used for the Microsoft Store" -ForegroundColor White
