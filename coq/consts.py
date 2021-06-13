from os import name
from pathlib import Path

_TOP_LEVEL = Path(__file__).resolve().parent.parent
REQUIREMENTS = _TOP_LEVEL / "requirements.txt"

_VARS = _TOP_LEVEL / ".vars"

RT_DIR = _VARS / "runtime"
RT_PY = (
    RT_DIR / "Scripts" / "python.exe" if name == "nt" else RT_DIR / "bin" / "python3"
)
ARTIFACTS_DIR = _TOP_LEVEL / "artifacts"
DB_DIR = _VARS / "db"

CONFIG_YML = _TOP_LEVEL / "config" / "defaults.yml"
SETTINGS_VAR = "coq_settings"

