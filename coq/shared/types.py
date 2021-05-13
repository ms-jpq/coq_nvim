from typing import Protocol


class Collector(Protocol):
    async def add(self) -> None:
        pass
