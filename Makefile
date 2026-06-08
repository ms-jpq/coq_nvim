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

.DEFAULT_GOAL := all

VAR := .vars
CURL := curl --fail --location --remove-on-error --create-dirs --no-progress-meter

OS := $(shell uname -s | tr '[:upper:]' '[:lower:]' | sed -e 's/darwin/macos/')
ARCH := $(shell uname -m | sed -e 's/arm64/aarch64/')

.PHONY: all clean clobber lint test build fmt ci

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

build: .venv/bin/mypy
	.venv/bin/python3 -m ci

ci: .venv/bin/mypy
	.venv/bin/python3 -m coq.ci
	./ci/compile_v3.lua

$(VAR)/bin/stylua: | $(VAR)/bin
	URI='https://github.com/JohnnyMorganz/StyLua/releases/latest/download/stylua-$(OS)-$(ARCH).zip'
	$(CURL) -- "$$URI" | bsdtar --extract --file - --directory '$|'
	chmod +x '$@'

$(VAR)/opt/lua-language-server/bin/lua-language-server: | $(VAR)
	case "$$OSTYPE" in
	darwin*)
		LUALS_OS=darwin
		;;
	linux*)
		LUALS_OS=linux
		;;
	*)
		set -v
		exit 2
		;;
	esac
	case "$$HOSTTYPE" in
	arm64|aarch64)
		LUALS_ARCH=arm64
		;;
	x86_64)
		LUALS_ARCH=x64
		;;
	*)
		set -v
		exit 2
		;;
	esac
	V_LUALS="$$($(CURL) -- 'https://api.github.com/repos/LuaLS/lua-language-server/releases/latest' | jq --raw-output --exit-status -- '.tag_name')"
	URI="https://github.com/LuaLS/lua-language-server/releases/download/$$V_LUALS/lua-language-server-$$V_LUALS-$$LUALS_OS-$$LUALS_ARCH.tar.gz"
	mkdir -v -p -- '$(VAR)/opt/lua-language-server'
	$(CURL) -- "$$URI" | tar --extract --gzip --file - --directory '$(VAR)/opt/lua-language-server'

fmt: $(VAR)/bin/stylua
	git ls-files --deduplicate --stage -- '*.lua' | awk -- '$$1 !~ /^120000/ { print $$4 }' | tr -- '\n' '\0' | xargs -r -0 -n 1 -P 0 -- '$<' --

lint: $(VAR)/opt/lua-language-server/bin/lua-language-server | $(VAR)
	mkdir -v -p -- '$(VAR)/luals'
	'$<' --check '.' --configpath '.luarc.json' --logpath '$(VAR)/luals' --checklevel Warning

test:
	./test.lua

all: lint test
