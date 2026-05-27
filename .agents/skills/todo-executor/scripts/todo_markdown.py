#!/usr/bin/env python3

from __future__ import annotations

from dataclasses import dataclass
import pathlib
import re


HEADING_RE = re.compile(r"^(#{1,6})\s+(.*?)\s*$")
CHECKBOX_RE = re.compile(r"^(\s*)([-*+]|\d+\.)\s+\[([ xX])\]\s+(.*?)\s*$")
LIST_RE = re.compile(r"^(\s*)([-*+]|\d+\.)\s+(.*?)\s*$")


@dataclass(frozen=True)
class TodoItem:
    ordinal: int
    line_no: int
    kind: str
    section: str
    text: str
    checked: bool
    is_checkbox: bool


def section_path(headings: list[str]) -> str:
    parts = [heading for heading in headings if heading]
    return " > ".join(parts) if parts else "（根目录）"


def is_actionable_list_item(text: str) -> bool:
    stripped = text.strip()
    if not stripped:
        return False
    if stripped.endswith(":"):
        return False
    return True


def read_lines(path: pathlib.Path) -> list[str]:
    return path.read_text(encoding="utf-8").splitlines()


def parse_items(lines: list[str], include_checked: bool = False) -> list[TodoItem]:
    headings = [""] * 6
    raw_items: list[tuple[int, str, str, str, bool, bool]] = []

    for index, raw_line in enumerate(lines, start=1):
        heading_match = HEADING_RE.match(raw_line)
        if heading_match:
            level = len(heading_match.group(1))
            title = heading_match.group(2).strip()
            headings[level - 1] = title
            for later in range(level, len(headings)):
                headings[later] = ""
            continue

        checkbox_match = CHECKBOX_RE.match(raw_line)
        if checkbox_match:
            checked = checkbox_match.group(3).lower() == "x"
            if checked and not include_checked:
                continue
            text = checkbox_match.group(4).strip()
            if text:
                kind = "已完成" if checked else "待办"
                raw_items.append(
                    (index, kind, section_path(headings), text, checked, True)
                )
            continue

        list_match = LIST_RE.match(raw_line)
        if list_match:
            text = list_match.group(3).strip()
            if is_actionable_list_item(text):
                raw_items.append(
                    (index, "列表", section_path(headings), text, False, False)
                )

    items: list[TodoItem] = []
    for ordinal, (line_no, kind, section, text, checked, is_checkbox) in enumerate(
        raw_items, start=1
    ):
        items.append(
            TodoItem(
                ordinal=ordinal,
                line_no=line_no,
                kind=kind,
                section=section,
                text=text,
                checked=checked,
                is_checkbox=is_checkbox,
            )
        )
    return items


def load_items(
    path: pathlib.Path, include_checked: bool = False
) -> tuple[list[str], list[TodoItem]]:
    lines = read_lines(path)
    return lines, parse_items(lines, include_checked=include_checked)
