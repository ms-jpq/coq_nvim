#!/usr/bin/env bash

set -eu
set -o pipefail

cd "$(dirname "$0")" || exit 1


USE_XDG=0
for arg in "$@"
do
  if [[ "$arg" = '--xdg' ]]
  then
    USE_XDG=1
  fi
done


PREPEND="$PWD/.vars"
if [[ "$USE_XDG" -ne 0 ]]
then
  PREPEND="${XDG_DATA_HOME:-"$PWD"}/nvim/chadtree"
  mkdir -p "$PREPEND"
fi


RT_BIN="$PREPEND/runtime/bin"
RT_PY="$RT_BIN/python3"
export PATH="$RT_BIN:$PATH"


if [[ -x "$1" ]] && [[ -x "$RT_PY" ]]
then
  shift
  exec "$RT_PY" "$@"
else
  exec "$@"
fi
