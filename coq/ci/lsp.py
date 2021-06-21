from json import loads
from pathlib import Path
from subprocess import check_call, check_output

from std2.pickle import decode

from ..consts import TOP_LEVEL
from ..shared.settings import LSProtocol

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


def lsp() -> LSProtocol:
    raw = _build(_DOCKER_FILE)
    json = loads(raw)
    spec = {
        "cmp_item_kind": {
            str(val): key for key, val in sorted(json.items(), key=lambda t: t[0])
        }
    }
    specs: LSProtocol = decode(LSProtocol, spec)
    return specs

