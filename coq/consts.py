from os import environ, name
from pathlib import Path
from uuid import uuid4

TOP_LEVEL = Path(__file__).resolve().parent.parent
REQUIREMENTS = TOP_LEVEL / "requirements.txt"

VARS = TOP_LEVEL / ".vars"

RT_DIR = VARS / "runtime"
RT_PY = (
    RT_DIR / "Scripts" / "python.exe" if name == "nt" else RT_DIR / "bin" / "python3"
)
_ARTIFACTS_DIR = TOP_LEVEL / "artifacts"

_CONF_DIR = TOP_LEVEL / "config"
CONFIG_YML = _CONF_DIR / "defaults.yml"
COMPILATION_YML = _CONF_DIR / "compilation.yml"
TMP_DIR = TOP_LEVEL / "temp"

LSP_ARTIFACTS = _ARTIFACTS_DIR / "lsp.json"
SNIPPET_ARTIFACTS = _ARTIFACTS_DIR / "snippets.json"

SETTINGS_VAR = "coq_settings"
NS = uuid4().hex


DEBUG = "COQ_DEBUG" in environ

BUFFERS_DB = str(TMP_DIR / "buffers.sqlite3") if DEBUG else ":memory:"
TMUX_DB = str(TMP_DIR / "tmux.sqlite3") if DEBUG else ":memory:"
SNIPPET_DB = str(TMP_DIR / "snippet.sqlite3") if DEBUG else ":memory:"

