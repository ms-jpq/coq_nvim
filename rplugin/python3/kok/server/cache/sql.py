from os.path import join, realpath
from typing import AsyncIterator, Iterator, Optional, Tuple

from ...shared.sql import AConnection

__base__ = join(realpath(__file__), "sql")

_INIT = join(__base__, "init.sql")
_PRAGMA = join(__base__, "pragma.sql")
_POPULATE_EDITS = join(__base__, "populate_edits.sql")
_POPULATE_FILENAME = join(__base__, "populate_filenames.sql")
_POPULATE_LOCATION = join(__base__, "populate_locations.sql")
_QUERY = join(__base__, "query.sql")
_QUERY_FILENAME = join(__base__, "query_filename.sql")
_QUERY_LOCATION = join(__base__, "query_location.sql")


class DB:
    def __init__(self) -> None:
        self._conn = AConnection()

    async def init(self) -> None:
        async with await self._conn.execute_script(_PRAGMA):
            pass
        async with await self._conn.execute_script(_INIT):
            pass

    async def populate(
        self, filename: str, location: Tuple[int, int], edits: Iterator[str]
    ) -> None:
        def cont() -> None:
            c2 = self._conn._conn
            cursor = c2.cursor()
            try:
                cursor.execute(_QUERY_FILENAME)
                filename_id: Optional[int] = cursor.fetchone()
                if filename_id is None:
                    cursor.execute(_POPULATE_FILENAME, (filename,))
                    filename_id = cursor.lastrowid

                cursor.execute(_QUERY_LOCATION)
                location_id: Optional[int] = cursor.fetchone()
                if location_id is None:
                    cursor.execute(_POPULATE_LOCATION, (filename_id, *location))
                    location_id = cursor.lastrowid

                def c2() -> Iterator[Tuple[int, str]]:
                    for edit in edits:
                        yield location_id, edit

                cursor.executemany(_POPULATE_EDITS, c2())
                c2.commit()
            finally:
                cursor.close()

        await self._conn.chan.run(cont)

    async def query(
        self, filename: str, location: Tuple[int, int]
    ) -> AsyncIterator[str]:
        async with await self._conn.execute(_QUERY) as cursor:
            cursor.execute()
            pass
