#!/usr/bin/env python3

import os
import tarfile
from pathlib import Path
from common import upload, OS_NAME, COMPILE_CONFIG, HOME, print_message

# Skip upload for forks that don't have access to tmp.kiwix.org
if os.environ.get('GITHUB_REPOSITORY', '').lower() != 'kiwix/kiwix-build':
    print_message("Skipping failure log upload for fork: {}", os.environ.get('GITHUB_REPOSITORY', 'unknown'))
    exit(0)

ARCHIVE_NAME = Path(f"fail_log_{OS_NAME}_{COMPILE_CONFIG}.tar.gz")


files_to_archive = []
files_to_archive += HOME.glob("BUILD_*")
files_to_archive += [HOME / "SOURCE", HOME / "LOGS", HOME / "TOOLCHAINS"]

with tarfile.open(ARCHIVE_NAME, "w:xz") as tar:
    for name in set(files_to_archive):
        tar.add(str(name))

upload(ARCHIVE_NAME, "ci@tmp.kiwix.org:30022", "/data/tmp/ci")
