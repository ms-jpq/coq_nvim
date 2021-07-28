from datetime import datetime, timezone
from os import environ, sep
from pathlib import Path
from shutil import rmtree
from subprocess import check_call, check_output, run
from typing import Iterator

_TOP_LV = Path(__file__).resolve().parent.parent


def _git_identity() -> None:
    email = "ci@ci.ci"
    username = "ci-bot"
    check_call(("git", "config", "--global", "user.email", email))
    check_call(("git", "config", "--global", "user.name", username))


def _git_clone(path: Path) -> None:
    if path.is_dir():
        rmtree(path)

    token = environ["CI_TOKEN"]
    uri = f"https://ms-jpq:{token}@github.com/ms-jpq/coq.artifacts.git"
    check_call(("git", "clone", uri, str(path)))


def _build() -> None:
    check_call(("python3", "-m", "coq.ci"), cwd=_TOP_LV)


def _git_alert(cwd: Path) -> None:
    prefix = "ci"
    check_call(("git", "fetch"), cwd=cwd)
    remote_brs = check_output(("git", "branch", "--remotes"), text=True, cwd=cwd)

    def cont() -> Iterator[str]:
        for br in remote_brs.splitlines():
            b = br.strip()
            if b and "->" not in b:
                _, _, name = b.partition(sep)
                if name.startswith(prefix):
                    yield name

    refs = tuple(cont())

    if refs:
        check_call(("git", "push", "--delete", "origin", *refs), cwd=cwd)

    proc = run(("git", "diff", "--exit-code"), cwd=cwd)
    if proc.returncode:
        time = datetime.now(tz=timezone.utc).strftime("%Y-%m-%d_%H-%M-%S")
        brname = f"{prefix}--{time}"
        check_call(("git", "checkout", "-b", brname), cwd=cwd)
        check_call(("git", "add", "."), cwd=cwd)
        check_call(("git", "commit", "-m", f"update_artifacts: {time}"), cwd=cwd)
        check_call(("git", "push", "--set-upstream", "origin", brname), cwd=cwd)


def main() -> None:
    cwd = _TOP_LV / "coq.artifacts"
    _git_identity()
    _git_clone(cwd)
    _build()
    _git_alert(_TOP_LV)
    _git_alert(cwd)
