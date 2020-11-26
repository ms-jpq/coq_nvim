from os.path import join, realpath

__base__ = join(realpath(__file__), "sql")

_INIT = join(__base__, "init.sql")
_PRAGMA = join(__base__, "pragma.sql")
_POPULATE = join(__base__, "populate.sql")

from ...shared.sql import AConnection


class DB:
    def __init__(self) -> None:
        self._conn = AConnection()

    async def init(self) -> None:
        async with await self._conn.execute_script(_PRAGMA):
            pass
        async with await self._conn.execute_script(_INIT):
            pass