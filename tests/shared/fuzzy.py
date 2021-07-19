from unittest import TestCase

from ...coq.shared.fuzzy import metrics, osa_distance, quick_ratio


class EditD(TestCase):
    def test_1(self) -> None:
        lhs = ""
        rhs = ""
        d = osa_distance(lhs, rhs)
        self.assertEqual(d, 0)

    def test_2(self) -> None:
        lhs = "a"
        rhs = "b"
        d = osa_distance(lhs, rhs)
        self.assertEqual(d, 1)

    def test_3(self) -> None:
        lhs = "ca"
        rhs = "abc"
        d = osa_distance(lhs, rhs)
        self.assertEqual(d, 2)

    def test_4(self) -> None:
        lhs = "cac"
        rhs = "aca"
        d = osa_distance(lhs, rhs)
        self.assertEqual(d, 2)

    def test_5(self) -> None:
        lhs = "cacaca"
        rhs = "acacac"
        d = osa_distance(lhs, rhs)
        self.assertEqual(d, 3)

    def test_6(self) -> None:
        lhs = ""
        rhs = "abc"
        d = osa_distance(lhs, rhs)
        self.assertEqual(d, 3)


class QuickRatio(TestCase):
    def test_1(self) -> None:
        lhs = "a"
        rhs = "ab"
        ratio = quick_ratio(lhs, rhs)
        self.assertAlmostEqual(ratio, 1)

    def test_2(self) -> None:
        lhs = "ac"
        rhs = "ab"
        ratio = quick_ratio(lhs, rhs)
        self.assertAlmostEqual(ratio, 0.5)

    def test_3(self) -> None:
        lhs = "acb"
        rhs = "abc"
        ratio = quick_ratio(lhs, rhs)
        self.assertAlmostEqual(ratio, 1)

    def test_4(self) -> None:
        lhs = "abc"
        rhs = "abz"
        ratio = quick_ratio(lhs, rhs)
        self.assertAlmostEqual(ratio, 2 / 3)


class Metrics(TestCase):
    def test_1(self) -> None:
        cword = "ab"
        match = "abab"
        m = metrics(cword, match=match)
        self.assertEqual(m.prefix_matches, 2)
        self.assertEqual(m.num_matches, 2)
        self.assertEqual(m.consecutive_matches, 1)

