from os import sep
from pathlib import Path
from unittest import TestCase

from std2.platform import OS

from ....coq.clients.paths.worker import p_lhs, parse, segs, separate

_SEP = {sep}
_FUZZY = 0.6
_LOOK_AHEAD = 3


class Plhs(TestCase):
    def test_1(self) -> None:
        lhs = "${PWD}"
        l = p_lhs(OS.windows, lhs=lhs)
        self.assertEqual(l, "${PWD}")

    def test_2(self) -> None:
        lhs = "%PWD%"
        l = p_lhs(OS.windows, lhs=lhs)
        self.assertEqual(l, "%PWD%")

    def test_3(self) -> None:
        lhs = "%P WD%"
        l = p_lhs(OS.windows, lhs=lhs)
        self.assertEqual(l, "")

    def test_4(self) -> None:
        lhs = "D:"
        l = p_lhs(OS.windows, lhs=lhs)
        self.assertEqual(l, "D:")


class Separate(TestCase):
    def test_1(self) -> None:
        a = tuple(separate({","}, "1,2,3"))
        self.assertEqual(a, ("1", ",2", ",3"))

    def test_2(self) -> None:
        a = tuple(separate({",", "$"}, "1,2$3"))
        self.assertEqual(a, ("1", ",2", "$3"))

    def test_3(self) -> None:
        a = tuple(separate({",", "$", "@"}, "1,2$3,4"))
        self.assertEqual(a, ("1", ",2", "$3", ",4"))

    def test_4(self) -> None:
        a = tuple(separate({",", "$", "@"}, "1@2$3,4"))
        self.assertEqual(a, ("1", "@2", "$3", ",4"))

    def test_5(self) -> None:
        a = tuple(separate(set(), "1,2,3"))
        self.assertEqual(a, ("1,2,3",))


class Segs(TestCase):
    def test_1(self) -> None:
        line = "1/2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("/2",))

    def test_2(self) -> None:
        line = "./2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("./2",))

    def test_3(self) -> None:
        line = "1./2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("./2",))

    def test_4(self) -> None:
        line = "/1./2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("/1./2", "./2"))

    def test_5(self) -> None:
        line = "1$PWD/2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("$PWD/2",))

    def test_6(self) -> None:
        line = "1${PWD}/2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("${PWD}/2",))

    def test_7(self) -> None:
        line = "$POW /2"
        s = tuple(segs(_SEP, line))
        self.assertEqual(s, ("/2",))


class Parser(TestCase):
    def test_1(self) -> None:
        line = "./.gith"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".git"), "./.git/"),
                (Path(".gitignore"), "./.gitignore"),
                (Path(".github"), "./.github/"),
            ),
        )
        self.assertEqual(actual, expected)

    def test_2(self) -> None:
        line = "./.github"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp"),
                (Path(".github", "workflows"), "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_3(self) -> None:
        line = "./.github/"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp"),
                (Path(".github", "workflows"), "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_4(self) -> None:
        line = "abc./.gith"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".git"), "./.git/"),
                (Path(".gitignore"), "./.gitignore"),
                (Path(".github"), "./.github/"),
            ),
        )
        self.assertEqual(actual, expected)

    def test_5(self) -> None:
        line = "abc./.github"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp"),
                (Path(".github", "workflows"), "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_6(self) -> None:
        line = "abc./.github/"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path(".github", ".agp"), "./.github/.agp"),
                (Path(".github", "workflows"), "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_7(self) -> None:
        line = "/h"
        results = {
            *parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        }
        expected = (Path(sep, "home"), "/home/")
        self.assertIn(expected, results)

    def test_8(self) -> None:
        line = "~/.c"
        results = {
            *parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        }
        expected = (Path.home() / ".config", "~/.config/")
        self.assertIn(expected, results)

    def test_9(self) -> None:
        line = "$a$PWD/.gith"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path.cwd() / ".git", "$PWD/.git/"),
                (Path.cwd() / ".gitignore", "$PWD/.gitignore"),
                (Path.cwd() / ".github", "$PWD/.github/"),
            ),
        )
        self.assertEqual(actual, expected)

    def test_10(self) -> None:
        line = "$a${PWD}/.gith"
        actual = sorted(
            parse(
                _SEP,
                look_ahead=_LOOK_AHEAD,
                fuzzy_cutoff=_FUZZY,
                base=Path("."),
                line=line,
            )
        )
        expected = sorted(
            (
                (Path.cwd() / ".git", "${PWD}/.git/"),
                (Path.cwd() / ".gitignore", "${PWD}/.gitignore"),
                (Path.cwd() / ".github", "${PWD}/.github/"),
            ),
        )
        self.assertEqual(actual, expected)
