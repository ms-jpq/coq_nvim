from asyncio import gather, run
from pathlib import Path

from std2.asyncio.subprocess import call

_PARENT = Path(__file__).resolve(strict=True).parent
_TOP_LEVEL = _PARENT.parent


async def _build(path: str) -> None:
    tag = f"coq_{path.lstrip('_')}"
    await call(
        "docker",
        "buildx",
        "build",
        "--progress",
        "plain",
        "--file",
        _PARENT / path / "Dockerfile",
        "--tag",
        tag,
        "--",
        _TOP_LEVEL,
        capture_stdout=False,
        capture_stderr=False,
    )


async def main() -> None:
    await _build("_base")
    await gather(_build("packer"), _build("vimplug"))


run(main())
