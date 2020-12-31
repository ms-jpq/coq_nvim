from asyncio import (
    StreamReader,
    StreamWriter,
    gather,
    open_unix_connection,
    start_unix_server,
)
from pathlib import PurePath

from forechan import Chan
from forechan.types import ChanClosed


async def transmit(writer: StreamWriter, ch: Chan[bytes]) -> None:
    async for data in ch:
        writer.write(data)
        writer.write("\0")
        await writer.drain()
    writer.close()


async def receive(reader: StreamReader, ch: Chan[bytes]) -> None:
    while ch:
        data = await reader.readuntil("\0")
        try:
            await ch.send(data)
        except ChanClosed:
            break
    reader.feed_eof()


async def start_client(path: PurePath, tx: Chan[bytes], rx: Chan[bytes]) -> None:
    reader, writer = await open_unix_connection(path)

    await gather(transmit(writer, ch=tx), receive(reader, ch=rx))


async def start_server(path: PurePath, tx: Chan[bytes], rx: Chan[bytes]) -> None:
    async def handler(reader: StreamReader, writer: StreamWriter) -> None:
        await gather(transmit(writer, ch=tx), receive(reader, ch=rx))

    server = await start_unix_server(handler, path=path)
    await server.wait_closed()
