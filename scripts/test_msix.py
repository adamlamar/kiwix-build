#!/usr/bin/env python3
"""
Test script for MSIX creation functionality
"""

import sys
import tempfile
import shutil
from pathlib import Path

def create_test_app(test_dir):
    """Create a minimal test application for MSIX packaging"""
    # Create a dummy executable
    exe_path = test_dir / "kiwix-desktop.exe"
    with open(exe_path, 'w') as f:
        f.write("echo 'Test Kiwix Desktop'")
    
    # Create some dummy DLLs
    dll_files = ["test1.dll", "test2.dll", "aria2c.exe"]
    for dll in dll_files:
        dll_path = test_dir / dll
        with open(dll_path, 'w') as f:
            f.write(f"# Dummy {dll}")
    
    return test_dir

def test_msix_creation():
    """Test the MSIX creation process"""
    script_dir = Path(__file__).parent
    msix_script = script_dir / "create_msix_package.py"
    
    if not msix_script.exists():
        print(f"Error: MSIX script not found: {msix_script}")
        return False
    
    with tempfile.TemporaryDirectory() as temp_dir:
        temp_path = Path(temp_dir)
        
        # Create test app directory
        test_app_dir = temp_path / "test_app"
        test_app_dir.mkdir()
        create_test_app(test_app_dir)
        
        # Output MSIX path
        msix_output = temp_path / "test-kiwix.msix"
        
        # Test command
        import subprocess
        
        command = [
            sys.executable, str(msix_script),
            str(test_app_dir),
            str(msix_output),
            "--version", "1.0.0.0"
        ]
        
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                print("✓ MSIX creation test passed")
                print(f"  Output: {msix_output}")
                if msix_output.exists():
                    print(f"  File size: {msix_output.stat().st_size} bytes")
                return True
            else:
                print("✗ MSIX creation test failed")
                print(f"  Return code: {result.returncode}")
                print(f"  stdout: {result.stdout}")
                print(f"  stderr: {result.stderr}")
                return False
        
        except subprocess.TimeoutExpired:
            print("✗ MSIX creation test timed out")
            return False
        except Exception as e:
            print(f"✗ MSIX creation test error: {e}")
            return False

if __name__ == '__main__':
    print("Testing MSIX creation functionality...")
    success = test_msix_creation()
    sys.exit(0 if success else 1)