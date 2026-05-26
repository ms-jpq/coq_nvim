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

VAR := .vars
CURL := curl --fail --location --remove-on-error --create-dirs --no-progress-meter

OS := $(shell uname -s | tr '[:upper:]' '[:lower:]' | sed -e 's/darwin/macos/')
ARCH := $(shell uname -m | sed -e 's/arm64/aarch64/')

.PHONY: clean clobber lint test build fmt ci

clean:
	shopt -u failglob
	rm -v -rf -- .mypy_cache/ .venv/

clobber: clean
	shopt -u failglob
	rm -v -rf -- '$(VAR)'

$(VAR) $(VAR)/bin:
	mkdir -v -p -- '$@'

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

test:
	./test.lua

build: .venv/bin/mypy
	.venv/bin/python3 -m ci

ci: .venv/bin/mypy
	.venv/bin/python3 -m coq.ci

$(VAR)/bin/stylua: | $(VAR)/bin
	URI='https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-$(OS)-$(ARCH).zip'
	$(CURL) -- "$$URI" | bsdtar --extract --file - --directory '$|'
	chmod +x '$@'

fmt: $(VAR)/bin/stylua
	git ls-files --deduplicate --stage -- '*.lua' | awk -- '$$1 !~ /^120000/ { print $$4 }' | tr -- '\n' '\0' | xargs -r -0 -n 1 -P 0 -- '$<' --
