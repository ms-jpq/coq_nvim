from platform import machine
from shutil import unpack_archive, which
from string import Template

from std2.os import OS, os
from std2.urllib import urlopen

from ...consts import TIMEOUT

_VER = "https://update.tabnine.com/version"
_EXEC = "TabNine.exe" if os is OS.windows else "TabNine"
_DOWN = Template(f"https://update.tabnine.com/$version/$triple/{_EXEC}")


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


def _download(ver: str) -> bytes:
    triple = _triple()
    ver = _version()
    uri = _DOWN.substitute(version=ver, triple=triple)
    with urlopen(uri, timeout=TIMEOUT) as resp:
        return resp.read()

