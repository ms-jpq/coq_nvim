from argparse import ArgumentParser, Namespace
from concurrent.futures import ThreadPoolExecutor
from contextlib import redirect_stderr, redirect_stdout
from io import StringIO
from multiprocessing import cpu_count
from pathlib import Path
from subprocess import DEVNULL, STDOUT, CalledProcessError, run
from sys import executable, exit, stderr, version_info
from textwrap import dedent
from typing import Union

from .consts import IS_WIN, REQUIREMENTS, RT_DIR, RT_PY, TOP_LEVEL, VARS

try:
    from shlex import join
    from typing import Literal

    if version_info < (3, 8, 2):
        raise ImportError()
except ImportError:
    print("⛔️ python < 3.8.2", file=stderr)
    exit(1)


def parse_args() -> Namespace:
    parser = ArgumentParser()

    sub_parsers = parser.add_subparsers(dest="command", required=True)

    s_run = sub_parsers.add_parser("run")
    s_run.add_argument("--socket", required=True)
    s_run.add_argument("--xdg")

    s_deps = sub_parsers.add_parser("deps")
    s_deps.add_argument("--xdg")

    return parser.parse_args()


args = parse_args()
command: Union[Literal["deps"], Literal["run"]] = args.command

_XDG = Path(args.xdg) if args.xdg is not None else None

_RT_DIR = _XDG / "coqrt" if _XDG else RT_DIR
_RT_PY = (
    (_RT_DIR / "Scripts" / "python.exe" if IS_WIN else _RT_DIR / "bin" / "python3")
    if _XDG
    else RT_PY
)
_LOCK_FILE = _RT_DIR / "requirements.lock"
_EXEC_PATH = Path(executable)
_EXEC_PATH = _EXEC_PATH.parent.resolve() / _EXEC_PATH.name
_REQ = REQUIREMENTS.read_text()

_IN_VENV = _RT_PY == _EXEC_PATH


if command == "deps":
    assert not _IN_VENV

    try:
        from venv import EnvBuilder

        print("...", flush=True)
        with redirect_stdout(StringIO()), redirect_stderr(StringIO()):
            EnvBuilder(
                system_site_packages=False,
                with_pip=True,
                upgrade=True,
                symlinks=not IS_WIN,
                clear=True,
            ).create(RT_DIR)
    except (ImportError, SystemExit, CalledProcessError):
        msg = "Please install python3-venv separately. (apt, yum, apk, etc)"
        print(msg, file=stderr)
        exit(1)
    else:
        proc = run(
            (
                RT_PY,
                "-m",
                "pip",
                "install",
                "--upgrade",
                "pip",
            ),
            cwd=TOP_LEVEL,
            stdin=DEVNULL,
            stderr=STDOUT,
        )
        if proc.returncode:
            print("Installation failed, check :message", file=stderr)
            exit(proc.returncode)
        proc = run(
            (
                RT_PY,
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
            stderr=STDOUT,
        )
        if proc.returncode:
            print("Installation failed, check :message", file=stderr)
            exit(proc.returncode)
        proc = run(
            ("git", "submodule", "update", "--recursive"),
            cwd=TOP_LEVEL,
            stdin=DEVNULL,
            stderr=STDOUT,
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
            print(dedent(msg), file=stderr)

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

        with ThreadPoolExecutor(max_workers=min(16, cpu_count() + 10)) as pool:
            code = run_client(nvim, pool=pool, client=CoqClient(pool=pool))
            exit(code)

else:
    assert False
