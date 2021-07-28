from pathlib import Path
from unittest import TestCase

from ....coq.clients.paths.worker import parse


class Parser(TestCase):
    def test_1(self) -> None:
        line = "./.gith"
        actual = sorted(parse(Path("."), line=line))
        expected = sorted(
            (("./.github/", "./.gith"),),
        )
        self.assertEqual(actual, expected)

    def test_2(self) -> None:
        line = "./.github"
        actual = sorted(parse(Path("."), line=line))
        expected = sorted(
            (
                ("./.github/.agp", "./.github"),
                ("./.github/workflows/", "./.github"),
            )
        )
        self.assertEqual(actual, expected)

    def test_3(self) -> None:
        line = "./.github/"
        actual = sorted(parse(Path("."), line=line))
        expected = sorted(
            (
                ("./.github/.agp", "/"),
                ("./.github/workflows/", "/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_4(self) -> None:
        line = "abc./.gith"
        actual = sorted(parse(Path("."), line=line))

        expected = sorted((("./.github/", "./.gith"),))
        self.assertEqual(actual, expected)

    def test_5(self) -> None:
        line = "abc./.github"
        actual = sorted(parse(Path("."), line=line))
        expected = sorted(
            (
                ("./.github/.agp", "./.github"),
                ("./.github/workflows/", "./.github"),
            )
        )
        self.assertEqual(actual, expected)

    def test_6(self) -> None:
        line = "abc./.github/"
        actual = sorted(parse(Path("."), line=line))

        expected = sorted(
            (
                ("./.github/.agp", "/"),
                ("./.github/workflows/", "/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_7(self) -> None:
        line = "/h"
        results = {*parse(Path("."), line=line)}
        expected = ("/home/", "/h")
        self.assertIn(expected, results)

    def test_8(self) -> None:
        line = "~/.c"
        results = {*parse(Path("."), line=line)}
        expected = ("~/.config/", "~/.c")
        self.assertIn(expected, results)
