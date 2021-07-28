#!/usr/bin/env python3

from argparse import ArgumentParser, Namespace
from pathlib import Path
from unittest import defaultTestLoader
from unittest.runner import TextTestRunner
from unittest.signals import installHandler

_TOP_LV = Path(__file__).resolve().parent
_TESTS = _TOP_LV / "tests"


def _parse_args() -> Namespace:
    parser = ArgumentParser()
    parser.add_argument("-v", "--verbosity", action="count", default=1)
    parser.add_argument("-f", "--fail", action="store_true", default=False)
    parser.add_argument("-b", "--buffer", action="store_true", default=False)
    parser.add_argument("-p", "--pattern", default="*.py")
    return parser.parse_args()


def main() -> None:
    args = _parse_args()
    suite = defaultTestLoader.discover(
        str(_TESTS), top_level_dir=str(_TOP_LV.parent), pattern=args.pattern
    )
    runner = TextTestRunner(
        verbosity=args.verbosity,
        failfast=args.fail,
        buffer=args.buffer,
    )

    installHandler()
    runner.run(suite)


main()
