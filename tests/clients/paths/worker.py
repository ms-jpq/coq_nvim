from os import sep
from pathlib import Path
from unittest import TestCase

from ....coq.clients.paths.worker import parse

_FUZZY = 0.6
_LOOK_AHEAD = 3


class Parser(TestCase):
    def test_1(self) -> None:
        line = "./.gith"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".git"), "./.git/", "./.gith"),
                (Path(".gitignore"), "./.gitignore", "./.gith"),
                (Path(".github"), "./.github/", "./.gith"),
            ),
        )
        self.assertEqual(actual, expected)

    def test_2(self) -> None:
        line = "./.github"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp", "./.github"),
                (Path(".github", "workflows"), "./.github/workflows/", "./.github"),
            )
        )
        self.assertEqual(actual, expected)

    def test_3(self) -> None:
        line = "./.github/"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp", "/"),
                (Path(".github", "workflows"), "./.github/workflows/", "/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_4(self) -> None:
        line = "abc./.gith"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(((Path(".github"), "./.github/", "./.gith"),))
        self.assertEqual(actual, expected)

    def test_5(self) -> None:
        line = "abc./.github"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp", "./.github"),
                (Path(".github", "workflows"), "./.github/workflows/", "./.github"),
            )
        )
        self.assertEqual(actual, expected)

    def test_6(self) -> None:
        line = "abc./.github/"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp", "/"),
                (Path(".github", "workflows"), "./.github/workflows/", "/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_7(self) -> None:
        line = "/h"
        results = {
            *parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        }
        expected = (Path(sep, "home"), "/home/", "/h")
        self.assertIn(expected, results)

    def test_8(self) -> None:
        line = "~/.c"
        results = {
            *parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        }
        expected = (Path.home() / ".config", "~/.config/", "~/.c")
        self.assertIn(expected, results)

    def test_9(self) -> None:
        line = "$a$PWD/.gith"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            ((Path.cwd() / ".github", "$PWD/.github/", "/.gith"),),
        )
        self.assertEqual(actual, expected)

    def test_10(self) -> None:
        line = "$a${PWD}/.gith"
        actual = sorted(
            parse(
                set(),
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path.cwd() / ".git", "${PWD}/.git/", "}/.gith"),
                (Path.cwd() / ".gitignore", "${PWD}/.gitignore", "}/.gith"),
                (Path.cwd() / ".github", "${PWD}/.github/", "}/.gith"),
            ),
        )
        self.assertEqual(actual, expected)
