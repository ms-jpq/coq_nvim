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

_CONF_DIR = TOP_LEVEL / "config"
LANG_ROOT = TOP_LEVEL / "locale"
DEFAULT_LANG = "en"
_DOC_DIR = TOP_LEVEL / "docs"


CONFIG_YML = _CONF_DIR / "defaults.yml"
COMPILATION_YML = _CONF_DIR / "compilation.yml"


CLIENTS_DIR = VARS / "clients"
TMP_DIR = VARS / "tmp"


_ART_DIR = TOP_LEVEL / "artifacts"
LSP_ARTIFACTS = _ART_DIR / "lsp.json"


SETTINGS_VAR = "coq_settings"


DEBUG = "COQ_DEBUG" in environ
DEBUG_METRICS = "COQ_DEBUG_METRICS" in environ
DEBUG_DB = "COQ_DEBUG_DB" in environ

BUFFER_DB = str(TMP_DIR / "buffers.sqlite3") if DEBUG_DB else ":memory:"
TREESITTER_DB = str(TMP_DIR / "treesitter.sqlite3") if DEBUG_DB else ":memory:"
SNIPPET_DB = str(TMP_DIR / "snippets.sqlite3") if DEBUG_DB else ":memory:"
INSERT_DB = str(TMP_DIR / "inserts.sqlite3") if DEBUG_DB else ":memory:"
TMUX_DB = str(TMP_DIR / "tmux.sqlite3") if DEBUG_DB else ":memory:"


_URI_BASE = "https://github.com/ms-jpq/coq_nvim/tree/bwaaak/docs/"

MD_README = _DOC_DIR / "README.md"
URI_README = _URI_BASE + MD_README.name

MD_CONF = _DOC_DIR / "CONF.md"
URI_CONF = _URI_BASE + MD_CONF.name

MD_KEYBIND = _DOC_DIR / "KEYBIND.md"
URI_KEYBIND = _URI_BASE + MD_KEYBIND.name

MD_FUZZY = _DOC_DIR / "FUZZY.md"
URI_FUZZY = _URI_BASE + MD_FUZZY.name

MD_DISPLAY = _DOC_DIR / "DISPLAY.md"
URI_DISPLAY = _URI_BASE + MD_DISPLAY.name

MD_SOURCES = _DOC_DIR / "SOURCES.md"
URI_SOURCES = _URI_BASE + MD_SOURCES.name

MD_MISC = _DOC_DIR / "MISC.md"
URI_MISC = _URI_BASE + MD_MISC.name

MD_STATISTICS = _DOC_DIR / "STATISTICS.md"
URI_STATISTICS = _URI_BASE + MD_STATISTICS.name

MD_PREF = _CONF_DIR / "PERFORMANCE.md"
URI_PREF = _URI_BASE + MD_PREF.name
