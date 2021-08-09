from asyncio import sleep
from contextlib import suppress
from os import X_OK, access
from pathlib import Path
from platform import machine
from shutil import which
from socket import timeout as TimeoutE
from string import Template
from tempfile import NamedTemporaryFile
from urllib.error import URLError

from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.platform import OS, os
from std2.urllib import urlopen

from ...consts import CLIENTS_DIR

T9_DIR = CLIENTS_DIR / "t9"
_LOCK = T9_DIR / "version.lock"

_VER = "https://update.tabnine.com/version"
_EXEC = "TabNine.exe" if os is OS.windows else "TabNine"
_DOWN = Template(f"https://update.tabnine.com/$version/$triple/{_EXEC}")

T9_BIN = T9_DIR / _EXEC


def _triple() -> str:
    arch = machine()
    if os is OS.linux:
        libc = "musl" if which("apk") else "gnu"
        return f"{arch}-unknown-linux-{libc}"
    elif os is OS.macos:
        return f"{arch}-apple-darwin"
    elif os is OS.windows:
        return f"{arch}-pc-windows-gnu"
    else:
        assert False


def _version(timeout: float) -> str:
    with urlopen(_VER, timeout=timeout) as resp:
        return resp.read().decode()


def _uri(timeout: float) -> str:
    triple = _triple()
    ver = _version(timeout)
    uri = _DOWN.substitute(version=ver, triple=triple)
    return uri


def _update(timeout: float) -> None:
    T9_DIR.mkdir(parents=True, exist_ok=True)
    try:
        p_uri = _LOCK.read_text()
    except FileNotFoundError:
        p_uri = ""

    uri = _uri(timeout)
    if not access(T9_BIN, X_OK) or uri != p_uri:
        with urlopen(uri, timeout=timeout) as resp:
            buf = resp.read()
        with suppress(FileNotFoundError), NamedTemporaryFile() as fd:
            fd.write(buf)
            fd.flush()
            Path(fd.name).replace(T9_BIN)

        T9_BIN.chmod(0o755)
        _LOCK.write_text(uri)


async def ensure_updated(retries: int, timeout: float) -> bool:
    for _ in range(retries):
        try:
            await run_in_executor(_update, timeout=timeout)
        except (URLError, TimeoutE) as e:
            log.warn("%s", e)
            await sleep(timeout)
        else:
            if access(T9_BIN, X_OK):
                return True
    else:
        return False
