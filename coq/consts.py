from pathlib import Path

_TOP_LEVEL = Path(__file__).resolve().parent.parent

_VARS = _TOP_LEVEL / ".vars"

RT_DIR = _VARS / "runtime"
