from pathlib import Path
from urllib.parse import urlparse

from ..coq.consts import COMPILATION_YML, TMP_DIR


def _p_name(uri: str) -> Path:
    return base / Path(urlparse(uri).path).name


def _git_pull() -> None:
    pass


def main() -> None:
    pass

