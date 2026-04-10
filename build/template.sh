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
pattern = re.compile(
    r"\.root_module\s*=\s*b\.createModule\(\.\{\s*"
    r"\.root_source_file\s*=\s*([^,]+),\s*"
    r"\.target\s*=\s*([^,]+),\s*"
    r"\.optimize\s*=\s*([^,]+),\s*"
    r"\}\),",
    re.S,
)
new, n = pattern.subn(
    ".root_source_file = \\1,\n        .target = \\2,\n        .optimize = \\3,",
    s,
    count=1,
)
if n == 0:
    raise SystemExit("Unable to patch build.zig for Zig 0.13 compatibility")
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
