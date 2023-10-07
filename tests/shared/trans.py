from itertools import accumulate, islice
from random import randint
from unittest import TestCase

from ...coq.shared.trans import reverse_acc, trans

_MIN_MATCH_LEN = 2


class ReverseAcc(TestCase):
    def test_1(self) -> None:
        seq = ""
        lhs = tuple(reverse_acc(0, seq=seq))
        rhs = tuple(reversed(tuple(accumulate(seq))))
        self.assertEqual(lhs, rhs)

    def test_2(self) -> None:
        seq = "".join(map(str, range(1, 5)))

        lhs = tuple(reverse_acc(0, seq=seq))
        rhs = tuple(reversed(tuple(accumulate(seq))))
        self.assertEqual(lhs, rhs)

    def test_3(self) -> None:
        gen = iter(lambda: str(randint(0, 88)), None)

        for _ in range(20):
            seq = "".join(islice(gen, 20))
            lhs = tuple(reverse_acc(0, seq=seq))
            rhs = tuple(reversed(tuple(accumulate(seq))))
            self.assertEqual(lhs, rhs)


class Trans(TestCase):
    def test_1(self) -> None:
        lhs, rhs = "", ""
        new_text = ""

        old_fixes = "", ""
        new_prefix = ""

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)

    def test_2(self) -> None:
        lhs, rhs = "a", "b"
        new_text = "ab"

        old_fixes = "", ""
        new_prefix = "ab"

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)

    def test_3(self) -> None:
        lhs, rhs = "abc", "de"
        new_text = "cd"

        old_fixes = "", ""
        new_prefix = "cd"

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)

    def test_4(self) -> None:
        lhs, rhs = "abb", "c"
        new_text = "bb"

        old_fixes = "bb", ""
        new_prefix = "bb"

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)

    def test_5(self) -> None:
        lhs, rhs = "abde", "fcg"
        new_text = "bde"

        old_fixes = "bde", ""
        new_prefix = "bde"

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)

    def test_6(self) -> None:
        lhs, rhs = "ab", "cdef"
        new_text = "bbcde"

        old_fixes = "", "cde"
        new_prefix = "bbcde"

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)

    def test_7(self) -> None:
        lhs, rhs = "abe", "cd"
        new_text = "abecf"

        old_fixes = "abe", ""
        new_prefix = "abecf"

        actual = trans(
            _MIN_MATCH_LEN,
            _MIN_MATCH_LEN,
            unifying_chars=set(),
            line_before=lhs,
            line_after=rhs,
            new_text=new_text,
        )
        self.assertEqual((actual.old_prefix, actual.old_suffix), old_fixes)
        self.assertEqual(actual.new_prefix, new_prefix)
