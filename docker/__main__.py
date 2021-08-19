from asyncio import gather, run
from pathlib import Path
from typing import Awaitable, Iterator

from std2.asyncio.subprocess import ProcReturn, call

_PARENT = Path(__file__).resolve().parent
_TOP_LEVEL = _PARENT.parent


async def main() -> None:
    await call(
        "docker",
        "buildx",
        "build",
        "--tag",
        "coq_base",
        "--",
        _PARENT / "_base" / "Dockerfile",
        cwd=_TOP_LEVEL,
    )

    def cont() -> Iterator[Awaitable[ProcReturn]]:
        for path in ("packer", "vimplug"):
            yield call(
                "docker",
                "buildx",
                "build",
                "--tag",
                f"coq_{path}",
                "--",
                _PARENT / path / "Dockerfile",
                cwd=_TOP_LEVEL,
            )

    await gather(*cont())


run(main())
