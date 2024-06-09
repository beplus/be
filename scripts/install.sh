#!/bin/bash
set -e

BE_PREFIX="$HOME/Tools"
mkdir -p $BE_PREFIX

BE_TOOLS_SRC_DIR="$BE_PREFIX/src"
mkdir -p $BE_TOOLS_SRC_DIR

echo 'export BE_PREFIX=$HOME/Tools' >> ~/.zshrc
echo 'export PATH="$BE_PREFIX/bin:$PATH"' >> ~/.zshrc
source ${ZDOTDIR:-$HOME}/.zshrc

git clone https://github.com/beplus/be "$BE_TOOLS_SRC_DIR/be"
cd "$BE_TOOLS_SRC_DIR/be"
make install
