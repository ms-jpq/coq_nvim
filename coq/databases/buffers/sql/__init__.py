"""
This file defines sql as a submodule of buffers/coq.
"""
from pathlib import Path

from ....shared.sql import loader

sql = loader(Path(__file__).resolve().parent)
