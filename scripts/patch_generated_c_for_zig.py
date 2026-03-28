#!/usr/bin/env python3

import re
import sys
from pathlib import Path


NAKED_HEADERS = {
    "__attribute__((naked)) int32_t libc_setjmp(",
    "__attribute__((naked)) void libc_longjmp(",
    "__attribute__((naked)) int32_t libc_sigsetjmp(",
    "__attribute__((naked)) void libc_siglongjmp(",
}


def patch_atomic_arg(match: re.Match[str]) -> str:
    op = match.group(1)
    expr = match.group(2).strip()

    if expr.startswith("(int32_t *)"):
        return match.group(0)
    if "->" not in expr and "." not in expr and "[" not in expr:
        return match.group(0)

    return f"__atomic_{op}((int32_t *)(&{expr}),"


def patch_compare_exchange(match: re.Match[str]) -> str:
    expr = match.group(1).strip()

    if expr.startswith("(int32_t *)"):
        return match.group(0)
    if "->" not in expr and "." not in expr and "[" not in expr:
        return match.group(0)

    return f"__atomic_compare_exchange_n((int32_t *)(&{expr}),"


def patch_text(text: str) -> str:
    text = text.replace(
        "int32_t main(int32_t argc, uint8_t * * argv)",
        "int32_t main(int32_t argc, char **argv)",
    )
    text = text.replace(
        "saved_argv = argv;",
        "saved_argv = (uint8_t **)argv;",
    )

    text = re.sub(
        r"__atomic_(store_n|load_n|fetch_add|fetch_sub)\(&([^,\n]+),",
        patch_atomic_arg,
        text,
    )
    text = re.sub(
        r"__atomic_compare_exchange_n\(\(&([^,\n\)]+)\),",
        patch_compare_exchange,
        text,
    )

    lines = text.splitlines(keepends=True)
    patched_lines: list[str] = []
    in_naked = False

    for line in lines:
        stripped = line.strip()

        if any(header in line for header in NAKED_HEADERS):
            in_naked = True
            patched_lines.append(line)
            continue

        if in_naked:
            if stripped in {"(void)env;", "(void)val;", "(void)savemask;", "return 0;"}:
                continue
            if stripped == "}":
                in_naked = False

        patched_lines.append(line)

    return "".join(patched_lines)


def main() -> int:
    if len(sys.argv) != 2:
        print("用法: patch_generated_c_for_zig.py <generated.c>", file=sys.stderr)
        return 1

    target = Path(sys.argv[1])
    original = target.read_text(encoding="utf-8", errors="surrogateescape")
    patched = patch_text(original)

    if patched != original:
        target.write_text(patched, encoding="utf-8", errors="surrogateescape")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
