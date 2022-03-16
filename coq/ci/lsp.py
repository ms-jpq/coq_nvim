from json import loads
from pathlib import Path
from typing import Any

from std2.asyncio.subprocess import call

_TOP_LV = Path(__file__).resolve(strict=True).parent
_DOCKER_FILE = _TOP_LV / "Dockerfile"


async def _build(dockerfile: Path) -> str:
    parent = dockerfile.parent
    name = f"coq_{parent.name}"
    await call(
        "docker",
        "buildx",
        "build",
        "--tag",
        name,
        "--file",
        str(dockerfile),
        "--progress",
        "plain",
        ".",
        cwd=parent,
        capture_stdout=False,
        capture_stderr=False,
    )
    proc = await call(
        "docker",
        "run",
        "--rm",
        name,
        cwd=_TOP_LV,
        capture_stderr=False,
    )
    return proc.stdout.decode()


async def lsp() -> Any:
    raw = await _build(_DOCKER_FILE)
    json = loads(raw)
    return json
