#!/usr/bin/env powershell

# Create basic MSIX package for signing test
param(
    [string]$OutputPath = "$env:TEMP\test-app.msix"
)

Write-Host "Creating basic MSIX package for signing test..." -ForegroundColor Yellow

# Create a minimal app directory structure
$appDir = "TestApp"
New-Item -ItemType Directory -Path $appDir -Force

# Create manifest content inline
$manifestContent = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10"
         xmlns:uap="http://schemas.microsoft.com/appx/manifest/uap/windows10"
         IgnorableNamespaces="uap">
  <Identity Name="TestApp" Version="1.0.0.0" Publisher="CN=Test" />
  <Properties>
    <DisplayName>Test App</DisplayName>
    <PublisherDisplayName>Test Publisher</PublisherDisplayName>
    <Logo>logo.png</Logo>
    <Description>Test application for signing</Description>
  </Properties>
  <Resources>
    <Resource Language="en-US" />
  </Resources>
  <Dependencies>
    <TargetDeviceFamily Name="Windows.Desktop" MinVersion="10.0.0.0" MaxVersionTested="10.0.0.0" />
  </Dependencies>
  <Applications>
    <Application Id="TestApp" Executable="test.exe" EntryPoint="TestApp.App">
      <uap:VisualElements DisplayName="Test App" Description="Test App" Square150x150Logo="logo.png" Square44x44Logo="smalllogo.png" BackgroundColor="blue" />
    </Application>
  </Applications>
</Package>
'@

$manifestDest = "$appDir\AppxManifest.xml"
Set-Content -Path $manifestDest -Value $manifestContent -Encoding UTF8

# Create a dummy executable (minimal PE header)
$dummyExe = [byte[]](0x4D, 0x5A)  # MZ header
[System.IO.File]::WriteAllBytes("$appDir\test.exe", $dummyExe)

# Create minimal 1x1 PNG files for logos
$pngBytes = [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54, 0x08, 0x99, 0x01, 0x01, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82)
[System.IO.File]::WriteAllBytes("$appDir\logo.png", $pngBytes)
[System.IO.File]::WriteAllBytes("$appDir\smalllogo.png", $pngBytes)

# Find MakeAppx tool
$makeAppxPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin\10.0.22621.0\x64\makeappx.exe"
if (-not (Test-Path $makeAppxPath)) {
  $WindowsKitsPath = "${env:ProgramFiles(x86)}\Windows Kits\10\bin"
  $makeAppxPath = Get-ChildItem -Path $WindowsKitsPath -Recurse -Filter "makeappx.exe" |
                 Where-Object { $_.Directory.Name -like "*x64*" } |
                 Sort-Object Name -Descending |
                 Select-Object -First 1 -ExpandProperty FullName
}

if (-not (Test-Path $makeAppxPath)) {
  Write-Error "MakeAppx not found. Please install Windows SDK."
  exit 1
}

# Create MSIX package
Write-Host "Using MakeAppx: $makeAppxPath" -ForegroundColor Cyan
Write-Host "Creating MSIX at: $OutputPath" -ForegroundColor Cyan

& $makeAppxPath pack /d $appDir /p $OutputPath

if ($LASTEXITCODE -ne 0) {
  Write-Error "Failed to create MSIX package (exit code: $LASTEXITCODE)"
  exit 1
}

if (Test-Path $OutputPath) {
  Write-Host "✅ MSIX package created successfully: $OutputPath" -ForegroundColor Green
  $size = (Get-Item $OutputPath).Length
  Write-Host "Package size: $($size) bytes" -ForegroundColor Gray
} else {
  Write-Error "MSIX package was not created"
  exit 1
}

# Clean up temporary directory
Remove-Item $appDir -Recurse -Force -ErrorAction SilentlyContinue
