from unittest import TestCase

from ....coq.clients.paths.worker import parse


class Parser(TestCase):
    def test_1(self) -> None:
        line = "./.gith"
        actual = sorted(parse(line))
        expected = sorted((("./.gith", "./.github/"),))
        self.assertEqual(actual, expected)

    def test_2(self) -> None:
        line = "./.github"
        actual = sorted(parse(line))
        expected = sorted(
            (
                ("./.github", "./.github/.agp"),
                ("./.github", "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_3(self) -> None:
        line = "./.github/"
        actual = sorted(parse(line))
        expected = sorted(
            (
                ("./.github/", "./.github/.agp"),
                ("./.github/", "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_4(self) -> None:
        line = "abc./.gith"
        actual = sorted(parse(line))
        expected = sorted((("./.gith", "./.github/"),))
        self.assertEqual(actual, expected)

    def test_5(self) -> None:
        line = "abc./.github"
        actual = sorted(parse(line))
        expected = sorted(
            (
                ("./.github", "./.github/.agp"),
                ("./.github", "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_6(self) -> None:
        line = "abc./.github/"
        actual = sorted(parse(line))
        expected = sorted(
            (
                ("./.github/", "./.github/.agp"),
                ("./.github/", "./.github/workflows/"),
            )
        )
        self.assertEqual(actual, expected)

    def test_7(self) -> None:
        line = "/h"
        results = {*parse(line)}
        expected = ("/h", "/home/")
        self.assertIn(expected, results)

