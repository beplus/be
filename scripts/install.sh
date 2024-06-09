#!/bin/bash
set -e

BE_PREFIX="$HOME/Tools"
mkdir -p $BE_PREFIX

BE_TOOLS_SRC_DIR="$BE_PREFIX/src"
mkdir -p $BE_TOOLS_SRC_DIR

ZSHRC="$HOME/.zshrc"

TEMP_FILE=$(mktemp)
awk '!/# @beplus\/be/ && !/export BE_PREFIX=\$HOME\/Tools/ && !/export PATH=\"\$BE_PREFIX\/bin:\$PATH\"/' $ZSHRC > $TEMP_FILE && mv $TEMP_FILE $ZSHRC

echo '# @beplus/be' >> $ZSHRC
echo 'export BE_PREFIX=$HOME/Tools' >> $ZSHRC
echo 'export PATH="$BE_PREFIX/bin:$PATH"' >> $ZSHRC

if [ -d "$BE_TOOLS_SRC_DIR/be" ]; then
  cd "$BE_TOOLS_SRC_DIR/be"
  git pull origin main
else
  git clone https://github.com/beplus/be "$BE_TOOLS_SRC_DIR/be"
  cd "$BE_TOOLS_SRC_DIR/be"
fi

echo ""
make install

echo ""
echo "Installation complete. Please restart your terminal."
