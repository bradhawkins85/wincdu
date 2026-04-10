#!/bin/bash
VERSION="ncdu-version"
bs_workspace="folder"

cd "${bs_workspace:?}" || exit 1
wget "https://dev.yorhel.nl/download/ncdu-${VERSION}.tar.gz"
tar xvf "ncdu-${VERSION}.tar.gz"

cd "ncdu-${VERSION:?}" || exit 1

./configure
make

strip *.exe
./ncdu --version
groff -mandoc -Thtml < ncdu.1 > ncdu.html

tar cvzf "../${bs_workspace}.tar.gz" ncdu.exe ncdu.html
