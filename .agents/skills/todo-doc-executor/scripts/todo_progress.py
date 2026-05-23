#!/usr/bin/env python3

from __future__ import annotations

import argparse
import pathlib
import sys

from todo_markdown import CHECKBOX_RE, TodoItem, load_items, parse_items


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="更新 Markdown TODO 进度并总结剩余工作。"
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    summary_parser = subparsers.add_parser(
        "summary", help="打印剩余可执行条目"
    )
    summary_parser.add_argument("path", help="Markdown TODO 文档路径")
    summary_parser.add_argument(
        "--limit",
        type=int,
        default=0,
        help="限制显示的剩余条目数量，0 表示不限制",
    )

    check_parser = subparsers.add_parser(
        "check", help="将未勾选的复选框条目标记为完成"
    )
    check_parser.add_argument("path", help="Markdown TODO 文档路径")
    check_parser.add_argument(
        "--line",
        action="append",
        type=int,
        default=[],
        help="要标记完成的未勾选复选框条目行号",
    )
    check_parser.add_argument(
        "--item",
        action="append",
        type=int,
        default=[],
        help="来自 todo_outline.py 的序号，用于标记完成",
    )
    check_parser.add_argument(
        "--dry-run",
        action="store_true",
        help="只预览变更，不写入文件",
    )
    check_parser.add_argument(
        "--no-summary",
        action="store_true",
        help="勾选条目后不打印剩余任务摘要",
    )

    return parser.parse_args()


def ensure_file(path: pathlib.Path) -> None:
    if not path.is_file():
        raise FileNotFoundError(path)


def format_item(item: TodoItem) -> str:
    return f"L{item.line_no} [{item.kind}] {item.section} :: {item.text}"


def print_summary_items(items: list[TodoItem], limit: int) -> int:
    if not items:
        print("没有剩余可执行条目。")
        return 0

    shown = items if limit <= 0 else items[:limit]
    print(f"剩余可执行条目：{len(items)}")
    current_section = None
    for item in shown:
        if item.section != current_section:
            current_section = item.section
            print(f"\n{current_section}")
        print(f"- {format_item(item)}")
    if limit > 0 and len(items) > limit:
        print(f"\n... 还有 {len(items) - limit} 项未显示")
    return 0


def print_summary(path: pathlib.Path, limit: int) -> int:
    try:
        _, items = load_items(path, include_checked=False)
    except OSError as exc:
        print(f"错误：读取失败 {path}：{exc}", file=sys.stderr)
        return 1
    return print_summary_items(items, limit)


def resolve_targets(
    all_items: list[TodoItem],
    pending_items: list[TodoItem],
    line_targets: list[int],
    item_targets: list[int],
) -> tuple[list[TodoItem], list[str]]:
    errors: list[str] = []
    selected: dict[int, TodoItem] = {}
    by_line = {item.line_no: item for item in all_items}
    by_item = {item.ordinal: item for item in pending_items}

    for line_no in line_targets:
        item = by_line.get(line_no)
        if item is None:
            errors.append(f"第 {line_no} 行：未找到可执行条目")
            continue
        selected[item.line_no] = item

    for ordinal in item_targets:
        item = by_item.get(ordinal)
        if item is None:
            errors.append(f"第 {ordinal} 项：不在当前待办大纲中")
            continue
        selected[item.line_no] = item

    return sorted(selected.values(), key=lambda item: item.line_no), errors


def mark_checked(line: str) -> str:
    match = CHECKBOX_RE.match(line)
    if match is None:
        return line
    return f"{match.group(1)}{match.group(2)} [x] {match.group(4)}"


def run_check(args: argparse.Namespace) -> int:
    path = pathlib.Path(args.path)
    try:
        ensure_file(path)
        lines, all_items = load_items(path, include_checked=True)
        _, pending_items = load_items(path, include_checked=False)
    except FileNotFoundError:
        print(f"错误：文件不存在：{path}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"错误：读取失败 {path}：{exc}", file=sys.stderr)
        return 1

    targets, errors = resolve_targets(all_items, pending_items, args.line, args.item)
    if not targets and not errors:
        print("错误：至少指定一个 --line 或 --item 目标", file=sys.stderr)
        return 1

    rejected: list[str] = []
    updatable: list[TodoItem] = []
    for item in targets:
        if not item.is_checkbox:
            rejected.append(
                f"L{item.line_no}：不是复选框条目，无法自动标记完成"
            )
            continue
        if item.checked:
            rejected.append(f"L{item.line_no}：已经勾选")
            continue
        updatable.append(item)

    for error in errors:
        print(f"警告：{error}", file=sys.stderr)
    for note in rejected:
        print(f"警告：{note}", file=sys.stderr)

    if not updatable:
        print("未更新任何复选框条目。")
        return 1 if errors else 0

    updated_lines = list(lines)
    for item in updatable:
        updated_lines[item.line_no - 1] = mark_checked(updated_lines[item.line_no - 1])

    if args.dry_run:
        print("试运行：以下条目将被标记为完成：")
    else:
        path.write_text("\n".join(updated_lines) + "\n", encoding="utf-8")
        print("已更新的复选框条目：")

    for item in updatable:
        print(f"- {format_item(item)}")

    if not args.no_summary:
        print("")
        summary_items = (
            parse_items(updated_lines, include_checked=False)
            if args.dry_run
            else load_items(path, include_checked=False)[1]
        )
        return print_summary_items(summary_items, limit=0)
    return 0


def main() -> int:
    args = parse_args()
    if args.command == "summary":
        path = pathlib.Path(args.path)
        if not path.is_file():
            print(f"错误：文件不存在：{path}", file=sys.stderr)
            return 1
        return print_summary(path, args.limit)
    if args.command == "check":
        return run_check(args)
    print("错误：不支持的命令", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
