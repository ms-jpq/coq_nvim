from os import environ, name
from pathlib import Path

TOP_LEVEL = Path(__file__).resolve().parent.parent
REQUIREMENTS = TOP_LEVEL / "requirements.txt"
TIMEOUT = 1

VARS = TOP_LEVEL / ".vars"

RT_DIR = VARS / "runtime"
RT_PY = (
    RT_DIR / "Scripts" / "python.exe" if name == "nt" else RT_DIR / "bin" / "python3"
)

_ARTIFACTS_DIR = TOP_LEVEL / "coq.artifacts"
_CONF_DIR = TOP_LEVEL / "config"
CONFIG_YML = _CONF_DIR / "defaults.yml"
COMPILATION_YML = _CONF_DIR / "compilation.yml"

CLIENTS_DIR = VARS / "clients"
TMP_DIR = VARS / "tmp"


LSP_ARTIFACTS = _ARTIFACTS_DIR / "lsp.json"
SNIPPET_ARTIFACTS = _ARTIFACTS_DIR / "snippets.json"

SETTINGS_VAR = "coq_settings"


DEBUG = "COQ_DEBUG" in environ
DEBUG_METRICS = "COQ_DEBUG_METRICS" in environ
DEBUG_DB = "COQ_DEBUG_DB" in environ

BUFFER_DB = str(TMP_DIR / "buffers.sqlite3") if DEBUG_DB else ":memory:"
SNIPPET_DB = str(TMP_DIR / "snippet.sqlite3") if DEBUG_DB else ":memory:"
INSERT_DB = str(TMP_DIR / "snippet.sqlite3") if DEBUG_DB else ":memory:"
TAGS_DB = str(TMP_DIR / "tags.sqlite3") if DEBUG_DB else ":memory:"
TMUX_DB = str(TMP_DIR / "tmux.sqlite3") if DEBUG_DB else ":memory:"

