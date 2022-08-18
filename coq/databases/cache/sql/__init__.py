"""
This file define sql as a submodule of client/cache.
"""
from pathlib import Path

from ....shared.sql import loader

sql = loader(Path(__file__).resolve(strict=True).parent)
