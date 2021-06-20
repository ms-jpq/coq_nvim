from unittest import TestCase

from ...coq.shared.trans import trans
from ...coq.shared.types import Edit


class Trans(TestCase):
    def test_1(self) -> None:
        lhs, rhs = "", ""
        edit = ""
        expected = "", ""
        actual = trans(lhs, rhs, edit=Edit(new_text=edit))
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_2(self) -> None:
        lhs, rhs = "a", "b"
        edit = "ab"
        expected = "a", "b"
        actual = trans(lhs, rhs, edit=Edit(new_text=edit))
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_3(self) -> None:
        lhs, rhs = "ab", "c"
        edit = "bc"
        expected = "b", "c"
        actual = trans(lhs, rhs, edit=Edit(new_text=edit))
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_4(self) -> None:
        lhs, rhs = "ab", "c"
        edit = "bb"
        expected = "b", ""
        actual = trans(lhs, rhs, edit=Edit(new_text=edit))
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

