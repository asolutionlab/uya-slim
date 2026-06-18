#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COMPILER="${UYA_COMPILER_BOOTSTRAP:-$ROOT_DIR/bin/uya}"
FIXTURE="$ROOT_DIR/tests/fixtures/upm/path_dep"
TMP_DIR="$(mktemp -d /tmp/uya_package_alias_source_roots.XXXXXX)"
WORK_DIR="$TMP_DIR/path_dep"
DEP_SRC="$WORK_DIR/hello_pkg/src"
CHECK_SRC="$TMP_DIR/check_alias_source_roots.uya"
CHECK_BIN="$TMP_DIR/check_alias_source_roots"
BUILD_LOG="$TMP_DIR/build.log"
RUN_LOG="$TMP_DIR/run.log"

cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

cp -R "$FIXTURE" "$WORK_DIR"
DEP_SRC_REAL="$(cd "$DEP_SRC" && pwd)/"
DEP_FILE_REAL="${DEP_SRC_REAL}file.uya"

cat > "$CHECK_SRC" <<EOF_CHECK
use libc;
use std.string.strcmp;
use driver;

fn is_directory(path: &byte) i32 {
    if path == null {
        return 0;
    }
    var st: Stat = Stat{};
    if stat(path as *byte, &st) == 0 {
        if ((st.st_mode as u32) & 61440u32) == 16384u32 {
            return 1;
        }
    }
    return 0;
}

fn main() i32 {
    var dep_dir: [byte: 4096] = [];
    var dep_file: [byte: 4096] = [];
    package_mode_alias_roots_clear();
    if package_mode_alias_roots_add("hello" as &byte, "$DEP_SRC_REAL" as &byte) != 0 {
        fprintf(libc.stderr, "alias root add failed\\n" as *byte);
        return 1;
    }
    if module_dir_exists("hello" as &byte, null, null, &dep_dir[0] as &byte, 4096usize) == 0 {
        fprintf(libc.stderr, "alias directory was not found\\n" as *byte);
        return 1;
    }
    if strcmp(&dep_dir[0] as *byte, "$DEP_SRC_REAL" as *byte) != 0 {
        fprintf(libc.stderr, "unexpected alias dir: %s\\n" as *byte, &dep_dir[0] as *byte);
        return 1;
    }
    if find_direct_module_file("hello.file" as &byte, null, null, &dep_file[0] as &byte, 4096usize) != 0 {
        fprintf(libc.stderr, "alias submodule file was not found\\n" as *byte);
        return 1;
    }
    if strcmp(&dep_file[0] as *byte, "$DEP_FILE_REAL" as *byte) != 0 {
        fprintf(libc.stderr, "unexpected alias file: %s\\n" as *byte, &dep_file[0] as *byte);
        return 1;
    }
    package_mode_alias_roots_clear();
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

echo "verify_package_alias_source_roots: ok"
