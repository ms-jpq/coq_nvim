from collections import OrderedDict, UserDict
from typing import Generic, TypeVar, cast

K = TypeVar("K")
V = TypeVar("V")


class LRU(UserDict, Generic[K, V]):
    def __init__(self, size: int) -> None:
        assert size > 0
        self._size = size
        self.data = OrderedDict()

    def __setitem__(self, key: K, item: V) -> None:
        if len(self) >= self._size:
            cast(OrderedDict, self.data).popitem(last=False)
        return super().__setitem__(key, item)

