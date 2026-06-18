#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${UYA_COMPILER_BOOTSTRAP:-$ROOT_DIR/bin/uya}"
FIXTURE="$ROOT_DIR/tests/fixtures/upm/path_dep"
TMP_DIR="$(mktemp -d /tmp/uya_upm_graph_plan_no_staging.XXXXXX)"
WORK_DIR="$TMP_DIR/path_dep"
APP_DIR="$WORK_DIR/app"
DEP_SRC="$WORK_DIR/hello_pkg/src"
CHECK_SRC="$TMP_DIR/check_graph_plan.uya"
CHECK_BIN="$TMP_DIR/check_graph_plan"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cp -R "$FIXTURE" "$WORK_DIR"
DEP_SRC_REAL="$(cd "$DEP_SRC" && pwd)/"

cat > "$CHECK_SRC" <<EOF_CHECK
use libc;
use std.string.strcmp;
use cmd.upm.upm_lib.types.UPMPackageBuildPlan;
use cmd.upm.upm_lib.types.upm_build_plan_init;
use cmd.upm.upm_lib.build_plan.upm_prepare_package_graph_plan;

fn main() i32 {
    var plan: UPMPackageBuildPlan = upm_build_plan_init();
    if upm_prepare_package_graph_plan("$APP_DIR" as &byte, null, &plan, 0) != 0 {
        fprintf(libc.stderr, "graph plan prepare failed\\n" as *byte);
        return 1;
    }
    if plan.active == 0 {
        fprintf(libc.stderr, "graph plan did not activate package mode\\n" as *byte);
        return 1;
    }
    if plan.build_root[0] != 0 as byte {
        fprintf(libc.stderr, "graph plan unexpectedly materialized staging root: %s\\n" as *byte, &plan.build_root[0] as *byte);
        return 1;
    }
    if strcmp(&plan.module_root[0] as *byte, &plan.source_root[0] as *byte) != 0 {
        fprintf(libc.stderr, "module root should be source root in graph-only package mode\\n" as *byte);
        return 1;
    }
    if plan.resolved_graph.dep_count < 1 {
        fprintf(libc.stderr, "graph plan did not resolve dependencies\\n" as *byte);
        return 1;
    }
    if strcmp(&plan.resolved_graph.deps[0].alias[0] as *byte, "hello" as *byte) != 0 {
        fprintf(libc.stderr, "unexpected dependency alias: %s\\n" as *byte, &plan.resolved_graph.deps[0].alias[0] as *byte);
        return 1;
    }
    if strcmp(&plan.resolved_graph.deps[0].source_root[0] as *byte, "$DEP_SRC_REAL" as *byte) != 0 {
        fprintf(libc.stderr, "unexpected dependency source root: %s\\n" as *byte, &plan.resolved_graph.deps[0].source_root[0] as *byte);
        return 1;
    }
    return 0;
}
EOF_CHECK

if ! "$COMPILER" build "$CHECK_SRC" -o "$CHECK_BIN" --no-split-c --project-root "$ROOT_DIR/src/" >"$BUILD_LOG" 2>&1; then
    cat "$BUILD_LOG" >&2
    exit 1
fi
if ! "$CHECK_BIN" >"$RUN_LOG" 2>&1; then
    cat "$RUN_LOG" >&2
    exit 1
fi
test -f "$APP_DIR/uya.lock"

echo "verify_upm_graph_plan_no_staging: ok"
