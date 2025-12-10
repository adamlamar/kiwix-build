#!/usr/bin/env python3

import sys, subprocess, shutil, argparse, os
from pathlib import Path

parser = argparse.ArgumentParser()

parser.add_argument("install_dir")
parser.add_argument("out_dir")
parser.add_argument("--static_dir")
parser.add_argument("archive_path", help="The full path of the archive to create")
parser.add_argument("-s", "--sign", action="store_true")
parser.add_argument("--msix", action="store_true", help="Also create MSIX package")
parser.add_argument("--version", help="Version for MSIX package")

args = parser.parse_args()

install_dir = Path(args.install_dir)
if args.static_dir:
    static_dir = Path(args.static_dir)
else:
    static_dir = install_dir

out_dir = Path(args.out_dir)
archive_path = Path(args.archive_path)

out_dir.mkdir(parents=True, exist_ok=True)

print(
    f"""Packaging kiwix-desktop
- From {install_dir}
- Static dir is {static_dir}
- Working dir {out_dir}
- Archive path is {archive_path}
- Python version {sys.version}"""
)

shutil.copy2(install_dir / "bin" / "kiwix-desktop.exe", out_dir)
subprocess.run(["windeployqt", "--compiler-runtime", str(out_dir)], check=True)


shutil.copy2(static_dir / "bin" / "aria2c.exe", out_dir)

for dll in (static_dir / "bin").glob("*.dll"):
    shutil.copy2(dll, out_dir)


# Copy ssl stuff
ssl_directory = Path("C:/") / "Program Files" / "OpenSSL"
shutil.copy2(ssl_directory / "libcrypto-3-x64.dll", out_dir)
shutil.copy2(ssl_directory / "libssl-3-x64.dll", out_dir)

if args.sign:
    # We assume here that signtool and certificate are properly configured.
    # Env var `SIGNTOOL_THUMBPRINT` must contain thumbprint of the certificate to use.
    command = [
        os.getenv("SIGNTOOL_PATH", "signtool.exe"),
        "sign",
        "/fd",
        "sha256",
        "/tr",
        "http://ts.ssl.com",
        "/td",
        "sha256",
        "/sha1",
        os.environ["SIGNTOOL_THUMBPRINT"],
        str(out_dir / "kiwix-desktop.exe"),
    ]
    subprocess.run(command, check=True)

print(
    f"""Create archive
- {archive_path.with_suffix('')}
- From {out_dir.parent}
- With {out_dir.name}"""
)
shutil.make_archive(
    archive_path.with_suffix(""), "zip", root_dir=out_dir, base_dir=""
)

# Create MSIX package if requested
if args.msix:
    print("Creating MSIX package...")
    msix_path = archive_path.with_suffix(".msix")

    # Get the version for MSIX package
    version = args.version
    if not version:
        # Try to extract version from a version file or use default
        version = "1.0.0.0"
        print(f"No version specified, using default: {version}")

    # Ensure version is in proper format (X.X.X.X)
    version_parts = version.split('.')
    if len(version_parts) < 4:
        version_parts.extend(['0'] * (4 - len(version_parts)))
    elif len(version_parts) > 4:
        version_parts = version_parts[:4]
    version = '.'.join(version_parts)

    # Path to MSIX creation script
    script_dir = Path(__file__).parent
    msix_script = script_dir / "create_msix_package.py"

    if msix_script.exists():
        try:
            # Create MSIX command
            msix_command = [
                sys.executable, str(msix_script),
                str(out_dir),
                str(msix_path),
                "--version", version
            ]

            if args.sign:
                msix_command.extend(["--sign"])
                if "SIGNTOOL_THUMBPRINT" in os.environ:
                    msix_command.extend(["--cert-thumbprint", os.environ["SIGNTOOL_THUMBPRINT"]])
                if "SIGNTOOL_PATH" in os.environ:
                    msix_command.extend(["--signtool-path", os.environ["SIGNTOOL_PATH"]])

            subprocess.run(msix_command, check=True)
            print(f"MSIX package created: {msix_path}")
        except subprocess.CalledProcessError as e:
            print(f"Warning: Failed to create MSIX package: {e}")
        except Exception as e:
            print(f"Warning: Error creating MSIX package: {e}")
    else:
        print(f"Warning: MSIX creation script not found: {msix_script}")
