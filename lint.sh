#!/usr/bin/env bash

set -eu
set -o pipefail


cd "$(dirname "$0")" || exit 1

cd "rplugin/python3/kok" || exit 1

FILES=(
  *.py
  **/*.py
  **/**/*.py
)
mypy -- "${FILES[@]}"
