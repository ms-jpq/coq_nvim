MAKEFLAGS += --jobs
MAKEFLAGS += --no-builtin-rules
MAKEFLAGS += --warn-undefined-variables
SHELL := bash
.DELETE_ON_ERROR:
.ONESHELL:
.SHELLFLAGS := -Eeuo pipefail -O dotglob -O nullglob -O extglob -O failglob -O globstar -c

.DEFAULT_GOAL := help

.PHONY: clean clobber lint test build fmt

clean:
	rm -rf -- .mypy_cache/ .venv/

clobber: clean
	rm -rf -- .vars/

.venv/bin/pip:
	python3 -m venv -- .venv

.venv/bin/mypy: .venv/bin/pip
	'$<' install --upgrade --requirement requirements.txt -- mypy types-PyYAML isort black

lint: .venv/bin/mypy
	'$<' -- .

test: .venv/bin/mypy
	.venv/bin/python3 -m tests

build: .venv/bin/mypy
	.venv/bin/python3 -m ci

fmt: .venv/bin/mypy
	.venv/bin/isort --profile=black --gitignore -- .
	.venv/bin/black --extend-exclude pack -- .
