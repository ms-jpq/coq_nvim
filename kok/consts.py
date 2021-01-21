from pathlib import Path

TOP_LEVEL = Path(__file__).resolve().parent.parent
_VARS = TOP_LEVEL / ".vars"
RT_DIR = _VARS / "runtime"
