#!/usr/bin/env python3

import os

from common import (
    run_kiwix_build,
    make_deps_archive,
    upload,
    print_message,
    HOME,
    COMPILE_CONFIG,
    DEV_BRANCH,
)
from build_definition import select_build_targets, DEPS
from common import HOME

# Check if dependencies are already built and cached
install_dir = HOME / "BUILD_win-amd64" / "INSTALL"
if install_dir.exists() and (install_dir / "bin").exists():
    print_message("Dependencies already cached and built, skipping compilation")
    exit(0)

for target in select_build_targets(DEPS):
    run_kiwix_build(target, config=COMPILE_CONFIG, build_deps_only=True)
    archive_file = make_deps_archive(target=target)
    if DEV_BRANCH:
        destination = "/data/tmp/ci/dev_preview/" + DEV_BRANCH
    else:
        destination = "/data/tmp/ci"
    # Skip upload for forks that don't have access to tmp.kiwix.org
    if os.environ.get('GITHUB_REPOSITORY', '').lower() == 'kiwix/kiwix-build':
        upload(archive_file, "ci@tmp.kiwix.org:30022", destination)
    else:
        print_message("Skipping deps upload for fork: {}", os.environ.get('GITHUB_REPOSITORY', 'unknown'))
    os.remove(str(archive_file))
