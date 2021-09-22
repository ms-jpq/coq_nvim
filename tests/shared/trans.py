from unittest import TestCase

from ...coq.shared.trans import trans


class Trans(TestCase):
    def test_1(self) -> None:
        lhs, rhs = "", ""
        new_text = ""
        expected = "", ""
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_2(self) -> None:
        lhs, rhs = "a", "b"
        new_text = "ab"
        expected = "a", "b"
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_3(self) -> None:
        lhs, rhs = "ab", "c"
        new_text = "bc"
        expected = "b", "c"
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_4(self) -> None:
        lhs, rhs = "ab", "c"
        new_text = "bb"
        expected = "b", ""
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_5(self) -> None:
        lhs, rhs = "abd", "efc"
        new_text = "bd"
        expected = "bd", ""
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_6(self) -> None:
        lhs, rhs = "ab", "c"
        new_text = "bbc"
        expected = "b", "c"
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)

    def test_7(self) -> None:
        lhs, rhs = "abe", "cd"
        new_text = "becf"
        expected = "be", ""
        actual = trans(lhs, rhs, new_text=new_text)
        self.assertEquals((actual.old_prefix, actual.old_suffix), expected)
