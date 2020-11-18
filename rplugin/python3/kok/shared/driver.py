from typing import Protocol


class OODA(Protocol):
    async def begin(self) -> None:
        pass

    async def run(self) -> None:
        pass
