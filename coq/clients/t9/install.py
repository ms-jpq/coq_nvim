from asyncio import sleep
from contextlib import suppress
from os import X_OK, access
from pathlib import Path, PurePath
from platform import machine
from shutil import which
from socket import timeout as TimeoutE
from string import Template
from tempfile import NamedTemporaryFile
from typing import Optional
from urllib.error import URLError

from pynvim_pp.lib import decode
from pynvim_pp.logging import log
from std2.asyncio import run_in_executor
from std2.platform import OS, os
from std2.urllib import urlopen

_VER = "https://update.tabnine.com/version"
_EXEC = "TabNine.exe" if os is OS.windows else "TabNine"
_DOWN = Template(f"https://update.tabnine.com/$version/$triple/{_EXEC}")


def _triple() -> Optional[str]:
    arch = machine()
    if os is OS.linux:
        libc = "musl" if which("apk") else "gnu"
        return f"{arch}-unknown-linux-{libc}"
    elif os is OS.macos:
        return f"{arch}-apple-darwin"
    elif os is OS.windows:
        return f"{arch}-pc-windows-gnu"
    else:
        return None


def _version(timeout: float) -> str:
    with urlopen(_VER, timeout=timeout) as resp:
        return decode(resp.read())


def _uri(timeout: float) -> Optional[str]:
    triple = _triple()
    if not triple:
        return None
    else:
        ver = _version(timeout)
        uri = _DOWN.substitute(version=ver, triple=triple)
        return uri


def t9_bin(vars_dir: Path) -> Path:
    return vars_dir / _EXEC


def _update(vars_dir: Path, timeout: float) -> bool:
    vars_dir.mkdir(parents=True, exist_ok=True)
    lock = vars_dir / "versions.lock"
    bin = t9_bin(vars_dir)

    try:
        p_uri = lock.read_text()
    except FileNotFoundError:
        p_uri = ""

    uri = _uri(timeout)
    if not uri:
        return False
    else:
        if not access(bin, X_OK) or uri != p_uri:
            with urlopen(uri, timeout=timeout) as resp:
                buf = resp.read()

            with suppress(FileNotFoundError), NamedTemporaryFile(dir=vars_dir) as fd:
                fd.write(buf)
                fd.flush()
                Path(fd.name).replace(bin)

            bin.chmod(0o755)
            lock.write_text(uri)

        return True


async def ensure_updated(
    vars_dir: Path, retries: int, timeout: float
) -> Optional[PurePath]:
    bin = t9_bin(vars_dir)
    for _ in range(retries):
        try:
            cont = await run_in_executor(_update, vars_dir=vars_dir, timeout=timeout)
        except (URLError, TimeoutE) as e:
            log.warn("%s", e)
            await sleep(timeout)
        else:
            if not cont:
                return None
            elif access(bin, X_OK):
                return bin
    else:
        return None
