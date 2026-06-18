#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESOLVER="$ROOT_DIR/src/cmd/upm/upm_lib/resolver.uya"
GIT_FETCHER="$ROOT_DIR/src/cmd/upm/upm_lib/git_fetch.uya"
FETCHER="$ROOT_DIR/src/cmd/upm/upm_lib/fetcher.uya"

grep -q 'export fn upm_fetch_prepare_checkout' "$GIT_FETCHER"
grep -q 'export enum UPMFetchBackend' "$FETCHER"
grep -q 'export fn upm_fetch_dependency_source' "$FETCHER"
grep -q 'UPM_FETCH_BACKEND_PATH' "$FETCHER"
grep -q 'UPM_FETCH_BACKEND_GIT' "$FETCHER"
grep -q 'UPM_FETCH_BACKEND_PROXY' "$FETCHER"
grep -q 'UPM_FETCH_BACKEND_REGISTRY' "$FETCHER"
grep -q 'upm_fetch_path_dependency' "$FETCHER"
grep -q 'upm_fetch_git_dependency' "$FETCHER"
grep -q 'upm_fetch_proxy_resolve_module_version' "$FETCHER"
grep -q 'upm_registry_resolve_module_version' "$FETCHER"
grep -q 'use cmd.upm.upm_lib.fetcher.upm_fetch_dependency_source;' "$RESOLVER"
if grep -q 'use cmd.upm.upm_lib.git_fetch.upm_fetch_prepare_checkout;' "$RESOLVER"; then
    echo "resolver must not call git fetch directly" >&2
    exit 1
fi
if grep -q 'use cmd.upm.upm_lib.fetch_proxy.upm_fetch_proxy_resolve_module_version;' "$RESOLVER"; then
    echo "resolver must not call proxy fetch directly" >&2
    exit 1
fi
if grep -q 'use cmd.upm.upm_lib.registry.upm_registry_resolve_module_version;' "$RESOLVER"; then
    echo "resolver must not call registry fetch directly" >&2
    exit 1
fi
if grep -q 'use cmd.upm.upm_lib.workspace.upm_workspace_resolve_module_version;' "$RESOLVER"; then
    echo "resolver must not call workspace fetch directly" >&2
    exit 1
fi
if grep -q 'upm_git_prepare_checkout' "$RESOLVER"; then
    echo "resolver must use the generic fetch boundary" >&2
    exit 1
fi

echo "verify_upm_fetch_boundary: ok"
