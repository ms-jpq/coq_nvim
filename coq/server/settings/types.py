from dataclasses import dataclass

from ...shared.protocol.types import Options


@dataclass(frozen=True)
class Settings:
    match_options: Options
