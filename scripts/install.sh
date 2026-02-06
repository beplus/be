#!/bin/bash
set -euo pipefail

CI_MODE="0"
if [[ "${1:-}" == "--ci" ]] || [[ "${CI:-}" == "true" ]] || [[ "${GITHUB_ACTIONS:-}" == "true" ]] || [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${CIRCLECI:-}" ]] || [[ -n "${TRAVIS:-}" ]]; then
  CI_MODE="1"
fi

# Respect pre-set BE_PREFIX; otherwise default
BE_PREFIX="${BE_PREFIX:-$HOME/.beplus}"
mkdir -p "$BE_PREFIX"

BE_TOOLS_SRC_DIR="$BE_PREFIX/src"
mkdir -p "$BE_TOOLS_SRC_DIR"

# Only modify shell rc locally (not in CI)
if [[ "$CI_MODE" == "0" ]]; then
  ZSHRC="$HOME/.zshrc"
  touch "$ZSHRC"

  TEMP_FILE=$(mktemp)
  awk '!/# @beplus\/be/ && !/export BE_PREFIX=\$HOME\/.beplus/ && !/export PATH=\"\$BE_PREFIX\/bin:\$PATH\"/' \
    "$ZSHRC" > "$TEMP_FILE" && mv "$TEMP_FILE" "$ZSHRC"

  {
    echo '# @beplus/be'
    echo 'export BE_PREFIX=$HOME/.beplus'
    echo 'export PATH="$BE_PREFIX/bin:$PATH"'
  } >> "$ZSHRC"
fi

if [ -d "$BE_TOOLS_SRC_DIR/be/.git" ]; then
  git -C "$BE_TOOLS_SRC_DIR/be" pull origin main
else
  git clone https://github.com/beplus/be "$BE_TOOLS_SRC_DIR/be"
fi

echo ""
make -C "$BE_TOOLS_SRC_DIR/be" install

echo ""
if [[ "$CI_MODE" == "0" ]]; then
  echo "Installation complete. Please restart your terminal."
else
  echo "Installation complete."
  echo "BE_PREFIX=$BE_PREFIX"
fi
