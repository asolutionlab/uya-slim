#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${UYA_CMD_BOOTSTRAP_COMPILER:-$ROOT_DIR/bin/uya}"
TMP_DIR="$(mktemp -d /tmp/uya_upm_graph_hash.XXXXXX)"
TMP_HOME="$TMP_DIR/home"
TMP_WORK="$TMP_DIR/tmp"
APP_DIR="$TMP_DIR/app"
DEP_DIR="$TMP_DIR/dep"
TEST_SRC="$TMP_DIR/check_graph_hash.uya"
TEST_BIN="$TMP_DIR/check_graph_hash"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$TMP_HOME" "$TMP_WORK" "$APP_DIR/src" "$DEP_DIR/src"

cat > "$APP_DIR/uya.toml" <<EOF_MANIFEST
[package]
name = "app"
module = "uya.local/app"
version = "0.1.0"
source-dir = "src"

[dependencies]
dep = { path = "../dep", module = "uya.local/dep", version = "1.2.3" }
EOF_MANIFEST

cat > "$APP_DIR/src/main.uya" <<'EOF_MAIN'
use dep.file.dep_value;

export fn main() i32 {
    return dep_value();
}
EOF_MAIN

cat > "$DEP_DIR/uya.toml" <<'EOF_DEP_MANIFEST'
[package]
name = "dep"
module = "uya.local/dep"
version = "1.2.3"
source-dir = "src"
EOF_DEP_MANIFEST

cat > "$DEP_DIR/src/file.uya" <<'EOF_DEP_SRC'
export fn dep_value() i32 {
    return 0;
}
EOF_DEP_SRC

cat > "$TEST_SRC" <<EOF_TEST
use libc.fprintf;
use cmd.upm.upm_lib.types.UPMManifest;
use cmd.upm.upm_lib.types.UPMResolvedGraph;
use cmd.upm.upm_lib.types.upm_manifest_init;
use cmd.upm.upm_lib.manifest.upm_parse_manifest;
use cmd.upm.upm_lib.resolver.upm_resolve_graph;

export fn main() i32 {
    var manifest: UPMManifest = upm_manifest_init();
    if upm_parse_manifest("$APP_DIR/uya.toml" as &byte, &manifest) != 0 {
        fprintf(libc.stderr, "parse manifest failed\\n" as *byte);
        return 1;
    }
    var graph: UPMResolvedGraph = UPMResolvedGraph{};
    if upm_resolve_graph(&manifest, &graph, 0) != 0 {
        fprintf(libc.stderr, "resolve graph failed\\n" as *byte);
        return 2;
    }
    if graph.dep_count != 1 {
        fprintf(libc.stderr, "unexpected dep_count=%d\\n" as *byte, graph.dep_count);
        return 3;
    }
    if graph.deps[0].content_hash[0] == 0 as byte {
        fprintf(libc.stderr, "missing graph content_hash\\n" as *byte);
        return 4;
    }
    return 0;
}
EOF_TEST

"$COMPILER" build "$TEST_SRC" -o "$TEST_BIN" --no-split-c --project-root "$ROOT_DIR/src/" >"$BUILD_LOG" 2>&1 || {
    cat "$BUILD_LOG"
    exit 1
}

HOME="$TMP_HOME" TMPDIR="$TMP_WORK" "$TEST_BIN" >"$RUN_LOG" 2>&1 || {
    cat "$RUN_LOG"
    exit 1
}
if [ -e "$APP_DIR/.uya/deps" ]; then
    echo "graph-only resolve unexpectedly materialized .uya/deps" >&2
    exit 1
fi

echo "verify_upm_resolved_graph_hash: ok"
