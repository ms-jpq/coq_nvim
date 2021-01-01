from asyncio import (
    StreamReader,
    StreamWriter,
    gather,
    open_unix_connection,
    start_unix_server,
)
from pathlib import PurePath
from typing import Awaitable, Tuple

from forechan import Chan
from forechan.types import ChanClosed


async def transmit(writer: StreamWriter, ch: Chan[bytes]) -> None:
    async for data in ch:
        writer.write(data)
        writer.write("\0")
        await writer.drain()
    writer.close()
    await writer.wait_closed()


async def receive(reader: StreamReader, ch: Chan[bytes]) -> None:
    while ch:
        data = await reader.readuntil("\0")
        try:
            await (ch << data)
        except ChanClosed:
            break
    reader.feed_eof()


async def start_client(path: PurePath, tx: Chan[bytes], rx: Chan[bytes]) -> None:
    reader, writer = await open_unix_connection(path)
    await gather(transmit(writer, ch=tx), receive(reader, ch=rx))


async def start_server(
    path: PurePath, tx_rx: Chan[Tuple[Chan[bytes], Chan[bytes]]]
) -> Awaitable[None]:
    async def handler(reader: StreamReader, writer: StreamWriter) -> None:
        tx, rx = await ([] << tx_rx)
        await gather(transmit(writer, ch=tx), receive(reader, ch=rx))

    server = await start_unix_server(handler, path=path)
    return server.wait_closed()
