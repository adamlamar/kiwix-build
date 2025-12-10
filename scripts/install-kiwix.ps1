# Install Kiwix Desktop MSIX Package
# This PowerShell script installs the Kiwix Desktop MSIX package

param(
    [Parameter(Mandatory=$true)]
    [string]$MsixPath,
    
    [switch]$Force,
    
    [switch]$DeveloperMode
)

# Check if running as administrator
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")

if (-not $isAdmin) {
    Write-Host "This script requires administrator privileges to install MSIX packages." -ForegroundColor Red
    Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Red
    exit 1
}

# Check if MSIX file exists
if (-not (Test-Path $MsixPath)) {
    Write-Host "MSIX file not found: $MsixPath" -ForegroundColor Red
    exit 1
}

Write-Host "Installing Kiwix Desktop MSIX package..." -ForegroundColor Green
Write-Host "Package: $MsixPath" -ForegroundColor Yellow

try {
    # Enable developer mode if requested (for unsigned packages)
    if ($DeveloperMode) {
        Write-Host "Checking developer mode settings..." -ForegroundColor Yellow
        $devMode = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -ErrorAction SilentlyContinue
        
        if ($null -eq $devMode -or $devMode.AllowDevelopmentWithoutDevLicense -eq 0) {
            Write-Host "Enabling developer mode for sideloading..." -ForegroundColor Yellow
            Set-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock" -Name "AllowDevelopmentWithoutDevLicense" -Value 1
        }
    }
    
    # Install the package
    $installArgs = @{
        Path = $MsixPath
    }
    
    if ($Force) {
        $installArgs.Force = $true
    }
    
    Write-Host "Installing package..." -ForegroundColor Yellow
    Add-AppxPackage @installArgs
    
    Write-Host "Successfully installed Kiwix Desktop!" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now:" -ForegroundColor Cyan
    Write-Host "- Find Kiwix Desktop in your Start Menu" -ForegroundColor White
    Write-Host "- Open ZIM files by double-clicking them" -ForegroundColor White
    Write-Host "- Launch from the Apps list" -ForegroundColor White
    
} catch {
    Write-Host "Failed to install MSIX package:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    
    if ($_.Exception.Message -match "0x80073D01") {
        Write-Host ""
        Write-Host "This error usually means the package is not signed or you need developer mode." -ForegroundColor Yellow
        Write-Host "Try running with the -DeveloperMode switch:" -ForegroundColor Yellow
        Write-Host "  .\install-kiwix.ps1 '$MsixPath' -DeveloperMode" -ForegroundColor Cyan
    }
    
    exit 1
}

# List installed packages to verify
Write-Host ""
Write-Host "Verifying installation..." -ForegroundColor Yellow
$installedPackage = Get-AppxPackage | Where-Object { $_.Name -like "*kiwix*" }

if ($installedPackage) {
    Write-Host "Installation verified!" -ForegroundColor Green
    Write-Host "Package Name: $($installedPackage.Name)" -ForegroundColor White
    Write-Host "Version: $($installedPackage.Version)" -ForegroundColor White
    Write-Host "Install Location: $($installedPackage.InstallLocation)" -ForegroundColor White
} else {
    Write-Host "Warning: Could not verify installation." -ForegroundColor Yellow
}