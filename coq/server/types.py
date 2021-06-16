from dataclasses import dataclass
from typing import Sequence
from uuid import UUID

from ..shared.types import PrimaryEdit, RangeEdit


@dataclass(frozen=True)
class UserData:
    ctx_uid: UUID
    primary_edit: PrimaryEdit
    secondary_edits: Sequence[RangeEdit]
