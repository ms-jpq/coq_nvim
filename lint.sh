#!/usr/bin/env bash

set -eu
set -o pipefail


cd "$(dirname "$0")" || exit 1


readarray -t -d $'\0' TRACKED < <(git ls-files --exclude-standard -z)
readarray -t -d $'\0' UNTRACKED < <(git ls-files --exclude-standard --others -z)

ALL_FILES=("${TRACKED[@]}" "${UNTRACKED[@]}")
PYTHON_FILES=()
for FILE in "${ALL_FILES[@]}";
do
  case "$FILE" in
    *.py)
      if [[ -f "$FILE" ]]
      then
        PYTHON_FILES+=("$PWD/$FILE")
      fi
      ;;
    *)
      ;;
  esac
done


mypy -- "${PYTHON_FILES[@]}"
