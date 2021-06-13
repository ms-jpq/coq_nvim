from os import name
from pathlib import Path

TOP_LEVEL = Path(__file__).resolve().parent.parent
REQUIREMENTS = TOP_LEVEL / "requirements.txt"

VARS = TOP_LEVEL / ".vars"

RT_DIR = VARS / "runtime"
RT_PY = (
    RT_DIR / "Scripts" / "python.exe" if name == "nt" else RT_DIR / "bin" / "python3"
)
ARTIFACTS_DIR = TOP_LEVEL / "artifacts"
DB_DIR = VARS / "db"

CONFIG_YML = TOP_LEVEL / "config" / "defaults.yml"
SETTINGS_VAR = "coq_settings"

