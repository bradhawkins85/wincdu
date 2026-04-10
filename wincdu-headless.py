#!/usr/bin/env python3
"""Generate a browsable HTML disk usage report.

This script provides a headless mode alternative to the interactive ncdu UI.
"""

from __future__ import annotations

import argparse
import html
import json
import os
from dataclasses import dataclass, field
from pathlib import Path
from typing import List


@dataclass
class Node:
    name: str
    path: str
    is_dir: bool
    size: int = 0
    error: str | None = None
    children: List["Node"] = field(default_factory=list)


def fmt_bytes(num: int) -> str:
    units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"]
    value = float(num)
    unit = units[0]
    for unit in units:
        if abs(value) < 1024 or unit == units[-1]:
            break
        value /= 1024.0
    if unit == "B":
        return f"{int(value)} {unit}"
    return f"{value:.2f} {unit}"


def scan(path: Path, follow_symlinks: bool = False) -> Node:
    root = path.resolve()

    def _walk(current: Path) -> Node:
        try:
            stat = current.stat(follow_symlinks=follow_symlinks)
        except OSError as exc:
            return Node(current.name or str(current), str(current), current.is_dir(), error=str(exc))

        if current.is_dir():
            node = Node(current.name or str(current), str(current), True)
            try:
                entries = sorted(list(current.iterdir()), key=lambda p: p.name.lower())
            except OSError as exc:
                node.error = str(exc)
                return node

            total = 0
            for entry in entries:
                child = _walk(entry)
                total += child.size
                node.children.append(child)
            node.size = total
            node.children.sort(key=lambda c: c.size, reverse=True)
            return node

        return Node(current.name, str(current), False, size=stat.st_size)

    root_node = _walk(root)
    root_node.name = str(root)
    return root_node


def flatten(node: Node, depth: int = 0, parent_id: str = "") -> list[dict]:
    current_id = f"{parent_id}/{node.name}" if parent_id else node.name
    rows = [
        {
            "id": current_id,
            "parent": parent_id or None,
            "name": node.name,
            "path": node.path,
            "size": node.size,
            "size_h": fmt_bytes(node.size),
            "type": "dir" if node.is_dir else "file",
            "depth": depth,
            "error": node.error,
            "child_count": len(node.children),
        }
    ]
    for child in node.children:
        rows.extend(flatten(child, depth + 1, current_id))
    return rows


def render(rows: list[dict], root_path: str) -> str:
    data = json.dumps(rows)
    safe_root = html.escape(root_path)
    return f"""<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">
<title>wincdu headless report - {safe_root}</title>
<style>
body {{ font-family: Segoe UI, Arial, sans-serif; margin: 0; background: #0b0f13; color: #e6edf3; }}
header {{ padding: 14px 18px; border-bottom: 1px solid #27313b; position: sticky; top: 0; background: #0b0f13; }}
#meta {{ color: #9fb1c1; font-size: 13px; margin-top: 6px; }}
main {{ padding: 12px 18px 24px; }}
table {{ width: 100%; border-collapse: collapse; table-layout: fixed; }}
th, td {{ text-align: left; padding: 7px 8px; border-bottom: 1px solid #1d252d; }}
th {{ color: #9fb1c1; font-weight: 600; font-size: 13px; }}
tr:hover td {{ background: #121922; }}
.size {{ width: 160px; text-align: right; font-variant-numeric: tabular-nums; }}
.type {{ width: 80px; color: #9fb1c1; }}
.path {{ width: 48%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #9fb1c1; }}
.name-cell {{ white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }}
.toggle {{ cursor: pointer; color: #78a6ff; user-select: none; margin-right: 6px; display: inline-block; width: 14px; }}
.file-dot {{ display: inline-block; width: 14px; color: #6b7785; margin-right: 6px; }}
.error {{ color: #ff9ea2; font-size: 12px; }}
.controls {{ margin-bottom: 10px; display: flex; gap: 10px; align-items: center; }}
input {{ background: #0f151c; border: 1px solid #27313b; color: #e6edf3; border-radius: 6px; padding: 6px 8px; min-width: 250px; }}
button {{ background: #1f6feb; border: none; color: #fff; border-radius: 6px; padding: 7px 11px; cursor: pointer; }}
</style>
</head>
<body>
<header>
  <h2 style=\"margin:0\">wincdu headless HTML report</h2>
  <div id=\"meta\">Root: {safe_root}</div>
</header>
<main>
  <div class=\"controls\">
    <input id=\"filter\" placeholder=\"Filter by name or path...\" />
    <button id=\"expand\">Expand all</button>
    <button id=\"collapse\">Collapse all</button>
  </div>
  <table>
    <thead><tr><th>Name</th><th class=\"size\">Size</th><th class=\"type\">Type</th><th class=\"path\">Path</th></tr></thead>
    <tbody id=\"rows\"></tbody>
  </table>
</main>
<script>
const rows = {data};
const expanded = new Set();
const byParent = new Map();
for (const r of rows) {{
  const p = r.parent || '__root__';
  if (!byParent.has(p)) byParent.set(p, []);
  byParent.get(p).push(r);
}}
for (const arr of byParent.values()) arr.sort((a,b)=>b.size-a.size);

function isVisible(row, q) {{
  let p = row.parent;
  while (p) {{
    if (!expanded.has(p)) return false;
    const pr = rows.find(x => x.id === p);
    p = pr ? pr.parent : null;
  }}
  if (!q) return true;
  const t = (row.name + ' ' + row.path).toLowerCase();
  return t.includes(q);
}}

function renderTable() {{
  const q = document.getElementById('filter').value.trim().toLowerCase();
  const tbody = document.getElementById('rows');
  tbody.innerHTML = '';
  for (const row of rows) {{
    if (!isVisible(row, q)) continue;
    const tr = document.createElement('tr');
    const hasChildren = row.child_count > 0;
    const open = expanded.has(row.id);
    const indent = '&nbsp;'.repeat(row.depth * 4);
    const icon = hasChildren ? `<span class="toggle" data-id="${{row.id}}">${{open ? '▾' : '▸'}}</span>` : '<span class="file-dot">·</span>';
    tr.innerHTML = `
      <td class="name-cell">${{indent}}${{icon}}${{escapeHtml(row.name)}}${{row.error ? `<div class="error">${{escapeHtml(row.error)}}</div>` : ''}}</td>
      <td class="size">${{escapeHtml(row.size_h)}}</td>
      <td class="type">${{row.type}}</td>
      <td class="path" title="${{escapeHtml(row.path)}}">${{escapeHtml(row.path)}}</td>
    `;
    tbody.appendChild(tr);
  }}
  document.querySelectorAll('.toggle').forEach(el => el.onclick = () => {{
    const id = el.getAttribute('data-id');
    if (expanded.has(id)) expanded.delete(id); else expanded.add(id);
    renderTable();
  }});
}}

function escapeHtml(s) {{
  return String(s)
    .replaceAll('&','&amp;')
    .replaceAll('<','&lt;')
    .replaceAll('>','&gt;')
    .replaceAll('"','&quot;')
    .replaceAll("'",'&#39;');
}}

document.getElementById('filter').addEventListener('input', renderTable);
document.getElementById('expand').onclick = () => {{ for (const r of rows) if (r.child_count) expanded.add(r.id); renderTable(); }};
document.getElementById('collapse').onclick = () => {{ expanded.clear(); if (rows[0]) expanded.add(rows[0].id); renderTable(); }};
if (rows[0]) expanded.add(rows[0].id);
renderTable();
</script>
</body>
</html>
"""


def main() -> int:
    parser = argparse.ArgumentParser(description="Generate browsable HTML disk usage report")
    parser.add_argument("scan_path", help="Directory to scan")
    parser.add_argument("output_html", help="Output HTML file path")
    parser.add_argument("--follow-symlinks", action="store_true", help="Follow symbolic links while scanning")
    args = parser.parse_args()

    scan_path = Path(args.scan_path)
    if not scan_path.exists():
        parser.error(f"Path does not exist: {scan_path}")
    if not scan_path.is_dir():
        parser.error(f"Path is not a directory: {scan_path}")

    root = scan(scan_path, follow_symlinks=args.follow_symlinks)
    rows = flatten(root)
    output_path = Path(args.output_html)
    output_path.write_text(render(rows, str(scan_path.resolve())), encoding="utf-8")
    print(f"Wrote report to {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
