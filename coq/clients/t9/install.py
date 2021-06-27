from platform import machine
from shutil import which
from string import Template

from std2.os import OS, os
from std2.urllib import urlopen

from ...consts import CLIENTS_DIR, TIMEOUT

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


def _version() -> str:
    with urlopen(_VER, timeout=TIMEOUT) as resp:
        return resp.read().decode()


def _uri() -> str:
    triple = _triple()
    ver = _version()
    uri = _DOWN.substitute(version=ver, triple=triple)
    return uri


def update(timeout: float) -> None:
    T9_DIR.mkdir(parents=True, exist_ok=True)
    try:
        p_uri = _LOCK.read_text()
    except FileNotFoundError:
        p_uri = ""

    uri = _uri()
    if uri != p_uri:
        with urlopen(uri, timeout=timeout) as resp:
            buf = resp.read()
        T9_BIN.write_bytes(buf)
        T9_BIN.chmod(0o755)
        _LOCK.write_text(uri)

