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
ARTIFACTS_DIR = TOP_LEVEL / "artifacts"
CONFIG_YML = TOP_LEVEL / "config" / "defaults.yml"
TMP_DIR = TOP_LEVEL / "temp"


SETTINGS_VAR = "coq_settings"
NS = uuid4().hex


DEBUG = "COQ_DEBUG" in environ

