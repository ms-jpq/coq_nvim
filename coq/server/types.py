from dataclasses import dataclass
from typing import Any, Optional, Sequence
from uuid import UUID

from ..shared.types import Doc, PrimaryEdit, RangeEdit


@dataclass(frozen=True)
class UserData:
    sort_by: str
    commit_uid: UUID
    primary_edit: PrimaryEdit
    secondary_edits: Sequence[RangeEdit]
    doc: Optional[Doc]
    extern: Optional[Any]

