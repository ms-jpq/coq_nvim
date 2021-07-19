from unittest import TestCase

from ...coq.shared.fuzzy import metrics, quick_ratio


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

