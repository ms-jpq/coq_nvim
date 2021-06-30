from json import loads
from pathlib import Path
from subprocess import check_call, check_output
from typing import Any

from ..consts import TOP_LEVEL

_DOCKER_FILE = TOP_LEVEL / "ci" / "Dockerfile"


def _build(dockerfile: Path) -> str:
    parent = dockerfile.parent
    name = f"coq_{parent.name}"
    check_call(
        (
            "docker",
            "build",
            "--tag",
            name,
            "--file",
            str(dockerfile),
            "--progress",
            "plain",
            ".",
        ),
        cwd=parent,
    )
    output = check_output(("docker", "run", "--rm", name), text=True)
    return output


def lsp() -> Any:
    raw = _build(_DOCKER_FILE)
    json = loads(raw)
    return json

