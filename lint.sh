#!/usr/bin/env bash

set -eu
set -o pipefail


cd "$(dirname "$0")" || exit 1


mypy --ignore-missing-imports -- clients/*.py clients/**/*.py rplugin/python3/fancy_completion/*.py rplugin/python3/fancy_completion/**/*.py
