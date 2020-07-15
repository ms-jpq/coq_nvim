#!/usr/bin/env bash

set -eu
set -o pipefail


cd "$(dirname "$0")" || exit 1

nvim --headless +UpdateRemotePlugin +quit
echo
exec nvim "$@"
