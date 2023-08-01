MAKEFLAGS += --check-symlink-times
MAKEFLAGS += --jobs
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --no-builtin-variables
MAKEFLAGS += --shuffle
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.DELETE_ON_ERROR:
.ONESHELL:
.SHELLFLAGS := --norc --noprofile -Eeuo pipefail -O dotglob -O nullglob -O extglob -O failglob -O globstar -c

.DEFAULT_GOAL := help

.PHONY: clean clobber lint test build fmt

clean:
	rm -v -rf -- .mypy_cache/ .venv/

clobber: clean
	rm -v -rf -- .vars/

.venv/bin/python3:
	python3 -m venv -- .venv

define PYDEPS
from itertools import chain
from os import execl
from sys import executable

from tomli import load

toml = load(open("pyproject.toml", "rb"))

project = toml["project"]
execl(
  executable,
  executable,
  "-m",
  "pip",
  "install",
  "--upgrade",
  "--",
  *project.get("dependencies", ()),
  *chain.from_iterable(project["optional-dependencies"].values()),
)
endef

.venv/bin/mypy: .venv/bin/python3
	'$<' -m pip install --requirement requirements.txt -- tomli
	'$<' <<< '$(PYDEPS)'

lint: .venv/bin/mypy
	'$<' -- .

test: .venv/bin/mypy
	.venv/bin/python3 -m tests

build: .venv/bin/mypy
	.venv/bin/python3 -m ci

fmt: .venv/bin/mypy
	.venv/bin/isort --profile=black --gitignore -- .
	.venv/bin/black -- .
