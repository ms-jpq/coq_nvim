#!/usr/bin/env bash

set -eu
set -o pipefail


cd "$(dirname "$0")" || exit 1

cd "rplugin/python3/fancy_completion" || exit 1

FILES=(
  *.py
  **/*.py
  **/**/*.py
)
mypy --ignore-missing-imports -- "${FILES[@]}"