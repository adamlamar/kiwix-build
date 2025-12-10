#!/usr/bin/env python3
"""
MSIX Packaging Script for Kiwix Desktop

This script creates an MSIX package for Kiwix Desktop on Windows.
It generates the necessary assets, processes the manifest template,
and uses the Windows SDK makeappx.exe tool to create the final MSIX package.
"""

import sys
import subprocess
import shutil
import argparse
import os
import tempfile
from pathlib import Path

try:
    from PIL import Image, ImageDraw
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False
    print("Warning: Pillow not available. Using fallback asset creation.")

def create_placeholder_asset(size, color, output_path):
    """Create a placeholder asset image with the specified size and color"""
    if not PIL_AVAILABLE:
        # Create a simple solid color bitmap manually
        create_simple_bitmap(size, color, output_path)
        return

    img = Image.new('RGBA', size, color)
    draw = ImageDraw.Draw(img)

    # Draw a simple "K" for Kiwix
    font_size = min(size) // 3
    text = "K"

    # Simple text drawing (fallback if no proper font available)
    try:
        # Try to get text size for centering
        bbox = draw.textbbox((0, 0), text)
        text_width = bbox[2] - bbox[0]
        text_height = bbox[3] - bbox[1]

        x = (size[0] - text_width) // 2
        y = (size[1] - text_height) // 2

        draw.text((x, y), text, fill='white')
    except:
        # Fallback: draw a simple rectangle
        margin = min(size) // 4
        draw.rectangle([margin, margin, size[0] - margin, size[1] - margin], fill='white')

    img.save(output_path, 'PNG')

def create_simple_bitmap(size, color, output_path):
    """Create a simple PNG without PIL (basic fallback)"""
    # This creates a very basic PNG file manually
    # For production, you might want to provide pre-built assets
    width, height = size

    # Create a very simple solid color PNG
    # This is a minimal implementation - in practice, you'd use proper assets
    with open(output_path, 'wb') as f:
        # PNG header
        f.write(b'\x89PNG\r\n\x1a\n')
        # Simple 1x1 PNG data (will be stretched by the system)
        png_data = b'\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x00\x00\x01\x00\x01\x00\x18\xdd\x8d\xb4\x00\x00\x00\x00IEND\xaeB`\x82'
        f.write(png_data)

def create_assets(assets_dir):
    """Create placeholder asset files for the MSIX package"""
    assets_dir.mkdir(parents=True, exist_ok=True)

    # Kiwix brand color (approximate)
    kiwix_color = (46, 125, 50, 255)  # Green color

    assets = {
        'StoreLogo.png': (50, 50),
        'Square44x44Logo.png': (44, 44),
        'Square150x150Logo.png': (150, 150),
        'Wide310x150Logo.png': (310, 150)
    }

    for filename, size in assets.items():
        asset_path = assets_dir / filename
        if not asset_path.exists():
            print(f"Creating placeholder asset: {filename}")
            create_placeholder_asset(size, kiwix_color, asset_path)

def process_manifest(template_path, output_path, version):
    """Process the manifest template and replace placeholders"""
    with open(template_path, 'r') as f:
        content = f.read()

    # Replace version placeholder
    content = content.replace('{VERSION}', version)

    with open(output_path, 'w') as f:
        f.write(content)

def copy_app_files(source_dir, dest_dir):
    """Copy application files to the MSIX package directory"""
    dest_dir.mkdir(parents=True, exist_ok=True)

    # Copy all files from the source directory
    for item in source_dir.iterdir():
        if item.is_file():
            shutil.copy2(item, dest_dir / item.name)
        elif item.is_dir():
            shutil.copytree(item, dest_dir / item.name, dirs_exist_ok=True)

def create_msix_package(package_dir, output_path):
    """Create the MSIX package using makeappx.exe"""
    # Try to find makeappx.exe in Windows SDK
    sdk_paths = [
        "C:/Program Files (x86)/Windows Kits/10/bin/10.0.26100.0/x64/makeappx.exe",
        "C:/Program Files (x86)/Windows Kits/10/bin/10.0.22621.0/x64/makeappx.exe",
        "C:/Program Files (x86)/Windows Kits/10/bin/10.0.19041.0/x64/makeappx.exe",
        "C:/Program Files (x86)/Windows Kits/10/bin/10.0.18362.0/x64/makeappx.exe",
        "C:/Program Files (x86)/Windows Kits/10/bin/10.0.17763.0/x64/makeappx.exe"
    ]

    makeappx_exe = None
    for sdk_path in sdk_paths:
        if Path(sdk_path).exists():
            makeappx_exe = sdk_path
            break

    if not makeappx_exe:
        # Try to find in PATH
        try:
            result = subprocess.run(["makeappx.exe"], capture_output=True, check=False)
            makeappx_exe = "makeappx.exe"
        except FileNotFoundError:
            pass

    if not makeappx_exe:
        # Try searching for Windows SDK installation
        try:
            if os.name == 'nt':  # Windows only
                import winreg
                key = winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows Kits\Installed Roots")
                kit_root = winreg.QueryValueEx(key, "KitsRoot10")[0]
                winreg.CloseKey(key)

                # Look for makeappx.exe in the kit root
                kit_path = Path(kit_root)
                for makeappx_path in kit_path.rglob("makeappx.exe"):
                    if "x64" in str(makeappx_path):
                        makeappx_exe = str(makeappx_path)
                        break
        except Exception:
            pass

    if not makeappx_exe:
        raise Exception(
            "makeappx.exe not found. Please install Windows SDK 10.\n"
            "Download from: https://developer.microsoft.com/en-us/windows/downloads/windows-sdk/"
        )

    print(f"Using makeappx.exe: {makeappx_exe}")

    # Create the MSIX package
    command = [
        makeappx_exe,
        "pack",
        "/d", str(package_dir),
        "/p", str(output_path),
        "/o"  # Overwrite existing package
    ]

    print(f"Creating MSIX package: {output_path}")
    result = subprocess.run(command, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Error creating MSIX package:")
        print(f"stdout: {result.stdout}")
        print(f"stderr: {result.stderr}")
        raise Exception(f"makeappx.exe failed with return code {result.returncode}")

    print("MSIX package created successfully!")

def sign_msix_package(msix_path, cert_thumbprint, signtool_path):
    """Sign the MSIX package with the provided certificate"""
    if not cert_thumbprint:
        print("No certificate thumbprint provided, skipping signing")
        return

    command = [
        signtool_path,
        "sign",
        "/fd", "sha256",
        "/tr", "http://ts.ssl.com",
        "/td", "sha256",
        "/sha1", cert_thumbprint,
        str(msix_path)
    ]

    print(f"Signing MSIX package...")
    result = subprocess.run(command, capture_output=True, text=True)

    if result.returncode != 0:
        print(f"Warning: Failed to sign MSIX package:")
        print(f"stdout: {result.stdout}")
        print(f"stderr: {result.stderr}")
    else:
        print("MSIX package signed successfully!")

def main():
    parser = argparse.ArgumentParser(description='Create MSIX package for Kiwix Desktop')
    parser.add_argument('source_dir', help='Directory containing the built application files')
    parser.add_argument('output_path', help='Output path for the MSIX file')
    parser.add_argument('--version', default='1.0.0.0', help='Package version (default: 1.0.0.0)')
    parser.add_argument('--template', help='Path to manifest template (default: templates/Package.appxmanifest)')
    parser.add_argument('--sign', action='store_true', help='Sign the package')
    parser.add_argument('--cert-thumbprint', help='Certificate thumbprint for signing')
    parser.add_argument('--signtool-path', default='signtool.exe', help='Path to signtool.exe')

    args = parser.parse_args()

    source_dir = Path(args.source_dir)
    output_path = Path(args.output_path)

    # Default template path
    if args.template:
        template_path = Path(args.template)
    else:
        # Try multiple possible locations for the template
        possible_paths = [
            Path.cwd() / 'templates' / 'Package.appxmanifest',  # Current working directory
            Path(__file__).parent.parent / 'templates' / 'Package.appxmanifest',  # Relative to script
            Path(os.environ.get('GITHUB_WORKSPACE', '.')) / 'templates' / 'Package.appxmanifest',  # GitHub workspace
            # Additional fallbacks for different environments
            Path(__file__).parent / '..' / 'templates' / 'Package.appxmanifest',  # Another relative path
            Path(os.path.dirname(os.path.abspath(__file__))) / '..' / 'templates' / 'Package.appxmanifest',  # Absolute script dir
            # Try searching from repository root
            Path(os.environ.get('GITHUB_WORKSPACE', '')) / 'templates' / 'Package.appxmanifest' if os.environ.get('GITHUB_WORKSPACE') else None
        ]

        # Filter out None entries
        possible_paths = [p for p in possible_paths if p is not None]

        template_path = None
        for path in possible_paths:
            try:
                # Resolve the path to handle '..' correctly
                resolved_path = path.resolve()
                if resolved_path.exists():
                    template_path = resolved_path
                    break
            except (OSError, RuntimeError):
                # Skip paths that can't be resolved
                continue

        if template_path is None:
            raise Exception(f"Manifest template not found. Tried: {[str(p) for p in possible_paths]}")

    if not source_dir.exists():
        raise Exception(f"Source directory not found: {source_dir}")

    print(f"Creating MSIX package for Kiwix Desktop")
    print(f"Source directory: {source_dir}")
    print(f"Template path: {template_path}")
    print(f"Template exists: {template_path.exists() if template_path else 'No template path'}")
    print(f"Output path: {output_path}")
    print(f"Version: {args.version}")
    print(f"Current working directory: {Path.cwd()}")
    print(f"Script directory: {Path(__file__).parent}")

    # Create temporary directory for package construction
    with tempfile.TemporaryDirectory() as temp_dir:
        package_dir = Path(temp_dir) / 'package'
        package_dir.mkdir()

        # Create assets directory
        assets_dir = package_dir / 'Assets'
        create_assets(assets_dir)

        # Process manifest
        manifest_path = package_dir / 'AppxManifest.xml'
        process_manifest(template_path, manifest_path, args.version)

        # Copy application files
        copy_app_files(source_dir, package_dir)

        # Create the MSIX package
        create_msix_package(package_dir, output_path)

        # Sign if requested
        if args.sign:
            sign_msix_package(
                output_path,
                args.cert_thumbprint or os.environ.get('SIGNTOOL_THUMBPRINT'),
                args.signtool_path
            )

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
