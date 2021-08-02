from argparse import ArgumentParser, Namespace
from os import name
from pathlib import Path
from shlex import join
from subprocess import DEVNULL, run
from sys import executable, exit, stderr, stdout, version_info
from textwrap import dedent
from typing import Union

from .consts import REQUIREMENTS, RT_DIR, RT_PY, TOP_LEVEL, VARS

if version_info < (3, 8, 2):
    msg = "⛔️ python < 3.8.2"
    print(msg, end="", file=stderr)
    exit(1)


from typing import Literal


def parse_args() -> Namespace:
    parser = ArgumentParser()

    sub_parsers = parser.add_subparsers(dest="command", required=True)

    s_run = sub_parsers.add_parser("run")
    s_run.add_argument("--socket", required=True)

    _ = sub_parsers.add_parser("deps")

    return parser.parse_args()


is_win = name == "nt"
args = parse_args()
command: Union[Literal["deps"], Literal["run"]] = args.command

_LOCK_FILE = RT_DIR / "requirements.lock"
_EXEC_PATH = Path(executable)
_REQ = REQUIREMENTS.read_text()

_IN_VENV = _EXEC_PATH == RT_PY


def _is_relative_to(origin: Path, *other: Path) -> bool:
    try:
        origin.relative_to(*other)
        return True
    except ValueError:
        return False


if command == "deps":
    assert not _IN_VENV

    try:
        from venv import EnvBuilder

        print("...", flush=True)
        if _is_relative_to(_EXEC_PATH, RT_DIR):
            pass
        else:
            EnvBuilder(
                system_site_packages=False,
                with_pip=True,
                upgrade=True,
                symlinks=not is_win,
                clear=True,
            ).create(RT_DIR)
    except (ImportError, SystemExit):
        print("Please install venv separately.", file=stderr)
        exit(1)
    else:
        proc = run(
            (
                str(RT_PY),
                "-m",
                "pip",
                "install",
                "--upgrade",
                "pip",
            ),
            cwd=TOP_LEVEL,
            stdin=DEVNULL,
            stderr=stdout,
        )
        if proc.returncode:
            print("Installation failed, check :message", file=stderr)
            exit(proc.returncode)
        proc = run(
            (
                str(RT_PY),
                "-m",
                "pip",
                "install",
                "--upgrade",
                "--force-reinstall",
                "--requirement",
                str(REQUIREMENTS),
            ),
            cwd=TOP_LEVEL,
            stdin=DEVNULL,
            stderr=stdout,
        )
        if proc.returncode:
            print("Installation failed, check :message", file=stderr)
            exit(proc.returncode)
        proc = run(
            ("git", "submodule", "update", "--recursive"),
            cwd=TOP_LEVEL,
            stdin=DEVNULL,
            stderr=stdout,
        )
        if proc.returncode:
            print("Installation failed, check :message", file=stderr)
            exit(proc.returncode)
        else:
            _LOCK_FILE.write_text(_REQ)
            msg = """
            ---
            You can now use :COQnow
            """
            msg = dedent(msg)
            print(msg, file=stderr)

elif command == "run":
    try:
        lock = _LOCK_FILE.read_text()
    except Exception:
        lock = ""
    try:
        if not _IN_VENV:
            raise ImportError()
        elif lock != _REQ:
            raise ImportError()
        else:
            import pynvim
            import pynvim_pp
            import std2
            import yaml
    except ImportError:
        msg = f"""
        Please update dependencies using :COQdeps
        -
        -
        Dependencies will be installed privately inside `{VARS}`
        `{join(("rm", "-rf", str(TOP_LEVEL.name)))}` will cleanly remove everything
        """
        msg = dedent(msg)
        print(msg, end="", file=stderr)
        exit(1)
    else:
        from pynvim import attach
        from pynvim_pp.client import run_client

        from .client import CoqClient

        nvim = attach("socket", path=args.socket)
        code = run_client(nvim, client=CoqClient())
        exit(code)

else:
    assert False
