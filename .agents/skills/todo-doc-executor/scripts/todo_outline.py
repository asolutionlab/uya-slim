#!/usr/bin/env python3

import argparse
import pathlib
import sys

from todo_markdown import load_items


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="从 Markdown TODO 文档打印可执行条目的有序大纲。"
    )
    parser.add_argument("path", help="Markdown TODO 文档路径")
    parser.add_argument(
        "--all",
        action="store_true",
        help="输出中包含已勾选的复选框条目",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    path = pathlib.Path(args.path)

    if not path.is_file():
        print(f"错误：文件不存在：{path}", file=sys.stderr)
        return 1

    try:
        _, items = load_items(path, include_checked=args.all)
    except OSError as exc:
        print(f"错误：读取失败 {path}：{exc}", file=sys.stderr)
        return 1

    if not items:
        print("未找到可执行列表项。")
        return 0

    for item in items:
        print(
            f"{item.ordinal:03d} | {item.kind:4} | "
            f"L{item.line_no:<4} | {item.section} | {item.text}"
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
