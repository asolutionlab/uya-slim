#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS=(
    "$ROOT_DIR/tests/test_cmd_dispatch.sh"
    "$ROOT_DIR/tests/verify_upm_legacy_mode.sh"
    "$ROOT_DIR/tests/verify_upm_manifest_flat.sh"
    "$ROOT_DIR/tests/verify_upm_manifest_src.sh"
    "$ROOT_DIR/tests/verify_upm_manifest_discovery_file.sh"
    "$ROOT_DIR/tests/verify_upm_manifest_missing.sh"
    "$ROOT_DIR/tests/verify_upm_missing_lockfile.sh"
    "$ROOT_DIR/tests/verify_upm_path_dep.sh"
    "$ROOT_DIR/tests/verify_upm_build_flags.sh"
    "$ROOT_DIR/tests/verify_upm_temp_cleanup.sh"
    "$ROOT_DIR/tests/verify_upm_path_invalid.sh"
    "$ROOT_DIR/tests/verify_upm_missing_dep_manifest.sh"
    "$ROOT_DIR/tests/verify_upm_alias_conflict.sh"
    "$ROOT_DIR/tests/verify_upm_transitive_conflict.sh"
    "$ROOT_DIR/tests/verify_upm_git_ref_conflict.sh"
    "$ROOT_DIR/tests/verify_upm_git_dep.sh"
    "$ROOT_DIR/tests/verify_upm_add_path.sh"
    "$ROOT_DIR/tests/verify_upm_add_git.sh"
    "$ROOT_DIR/tests/verify_upm_remove.sh"
    "$ROOT_DIR/tests/verify_upm_add_remove_e2e.sh"
)

for script in "${SCRIPTS[@]}"; do
    bash "$script"
done

echo "verify_upm_suite: ok"
