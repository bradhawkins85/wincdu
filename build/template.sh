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

./configure
make

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
