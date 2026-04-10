#!/bin/bash
set -euo pipefail

DEFAULT_NCDU_VERSION="2.9.1"
VERSION="${NCDU_VERSION:-${DEFAULT_NCDU_VERSION}}"
bs_workspace="${BS_WORKSPACE:-${1:-}}"

if [ -z "${bs_workspace}" ]; then
  echo "BS_WORKSPACE (or first script arg) must be set" >&2
  exit 1
fi

cd "${bs_workspace:?}" || exit 1

archive_url="https://dev.yorhel.nl/download/ncdu-${VERSION}.tar.gz"
if ! wget --spider "${archive_url}" > /dev/null 2>&1; then
  if [ "${VERSION}" != "${DEFAULT_NCDU_VERSION}" ]; then
    echo "Requested NCDU_VERSION=${VERSION} not found, falling back to ${DEFAULT_NCDU_VERSION}" >&2
    VERSION="${DEFAULT_NCDU_VERSION}"
    archive_url="https://dev.yorhel.nl/download/ncdu-${VERSION}.tar.gz"
  fi
fi

wget "${archive_url}"
tar xvf "ncdu-${VERSION}.tar.gz"

cd "ncdu-${VERSION:?}" || exit 1

if [ -x "./configure" ]; then
  ./configure
  make
elif [ -f "./build.zig" ]; then
  if ! command -v zig > /dev/null 2>&1; then
    echo "zig is required to build ncdu ${VERSION} (build.zig detected)" >&2
    exit 1
  fi

  if ! zig build -Doptimize=ReleaseSafe 2> /tmp/zig-build.err; then
    if grep -q "no field named 'root_module' in struct 'Build.ExecutableOptions'" /tmp/zig-build.err; then
      echo "Detected Zig 0.13/0.12 API mismatch, patching build.zig for compatibility..." >&2
      python3 - <<'PY'
from pathlib import Path
import re

p = Path("build.zig")
s = p.read_text()

def extract_field(body, field):
    m = re.search(rf"\.{field}\s*=\s*(.*?),\s*\n", body, re.S)
    return m.group(1).strip() if m else None

# Pattern 1: inline .root_module = b.createModule(.{...body...}),
inline_pat = re.compile(
    r"\.root_module\s*=\s*b\.createModule\(\.\{(?P<body>.*?)\}\s*\)\s*,",
    re.S,
)
m = inline_pat.search(s)
if m:
    body = m.group("body")
    fv = {}
    for field in ("root_source_file", "target", "optimize"):
        v = extract_field(body, field)
        if not v:
            raise SystemExit(f"Unable to locate .{field} inside root_module assignment")
        fv[field] = v
    replacement = (
        f".root_source_file = {fv['root_source_file']},\n"
        f"        .target = {fv['target']},\n"
        f"        .optimize = {fv['optimize']},"
    )
    p.write_text(s[:m.start()] + replacement + s[m.end():])
    raise SystemExit(0)

# Pattern 2: const VAR = b.createModule(.{...}); VAR.method(...); ... .root_module = VAR,
var_pat = re.compile(
    r"(?P<ws>[ \t]*)const\s+(?P<var>\w+)\s*=\s*b\.createModule\(\.\{(?P<body>.*?)\}\s*\)\s*;[ \t]*\n",
    re.S,
)
m = var_pat.search(s)
if not m:
    raise SystemExit("Unable to locate root_module assignment in build.zig")

varname = m.group("var")
body = m.group("body")
ws = m.group("ws")

# Extract fields from the module body to inline into addExecutable/addTest
fields = {}
for field in ("root_source_file", "target", "optimize", "strip", "link_libc"):
    v = extract_field(body, field)
    if v is not None:
        fields[field] = v

if "root_source_file" not in fields:
    raise SystemExit("Unable to locate .root_source_file inside createModule")

# Collect method calls on the module variable that follow its declaration
method_re = re.compile(rf"[ \t]*{re.escape(varname)}\.(\w+)\(([^;]*)\);[ \t]*\n")
pos = m.end()
methods = []
while True:
    mm = method_re.match(s, pos)
    if not mm:
        break
    # Strip trailing ", .{}" argument added in Zig 0.14 module API
    raw_args = re.sub(r",\s*\.\{\}\s*$", "", mm.group(2).strip())
    methods.append((mm.group(1), raw_args))
    pos = mm.end()

# Remove the createModule declaration and all following module method calls
new = s[:m.start()] + s[pos:]

# Build inline fields (replacing .root_module = varname,)
field_indent = "        "
inline_parts = "\n".join(f"{field_indent}.{f} = {v}," for f, v in fields.items())

# Replace ALL occurrences of .root_module = varname, (covers addExecutable and addTest)
root_mod_re = re.compile(rf"[ \t]*\.root_module\s*=\s*{re.escape(varname)}\s*,\n")
new = root_mod_re.sub(lambda _: inline_parts + "\n", new)

# Insert the collected method calls after the addExecutable statement
if methods:
    exe_match = re.search(r"const\s+(\w+)\s*=\s*b\.addExecutable\(", new)
    exe_var = exe_match.group(1) if exe_match else "exe"
    exe_stmt_re = re.compile(
        r"(const\s+" + re.escape(exe_var) + r"\s*=\s*b\.addExecutable\(.*?\}\s*\)\s*;[ \t]*\n)",
        re.S,
    )
    method_strs = "".join(f"{ws}{exe_var}.{name}({args});\n" for name, args in methods)
    new = exe_stmt_re.sub(lambda m: m.group(1) + method_strs, new, count=1)

p.write_text(new)
PY
      zig build -Doptimize=ReleaseSafe
    else
      cat /tmp/zig-build.err >&2
      exit 1
    fi
  fi

  if [ -f "./zig-out/bin/ncdu" ]; then
    cp ./zig-out/bin/ncdu ./ncdu
  else
    echo "ncdu binary not found under zig-out/bin after zig build" >&2
    exit 1
  fi
else
  echo "No supported build system detected (missing configure and build.zig)" >&2
  exit 1
fi

if compgen -G "./*.exe" > /dev/null; then
  strip -- ./*.exe
  NCDU_BIN="ncdu.exe"
else
  strip -- ./ncdu
  cp ./ncdu ./ncdu.exe
  NCDU_BIN="ncdu.exe"
fi

./ncdu --version
groff -mandoc -Thtml < ncdu.1 > ncdu.html

tar cvzf "../${bs_workspace}.tar.gz" "${NCDU_BIN}" ncdu.html
