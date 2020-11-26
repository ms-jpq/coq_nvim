from os.path import join, realpath
from ...shared.sql import AConnection

__base__ = join(realpath(__file__), "sql")

_INIT = join(__base__, "init.sql")
_PRAGMA = join(__base__, "pragma.sql")
_POPULATE_COUNT = join(__base__, "populate_counts.sql")
_POPULATE_FILENAME = join(__base__, "populate_filenames.sql")
_POPULATE_LOCATION = join(__base__, "populate_locations.sql")
_QUERY = join(__base__, "query.sql")


class DB:
    def __init__(self) -> None:
        self._conn = AConnection()

    async def init(self) -> None:
        async with await self._conn.execute_script(_PRAGMA):
            pass
        async with await self._conn.execute_script(_INIT):
            pass