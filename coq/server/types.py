from dataclasses import dataclass
from typing import Optional, Sequence
from uuid import UUID

from ..shared.types import PrimaryEdit, RangeEdit, Doc


@dataclass(frozen=True)
class UserData:
    commit_uid: UUID
    sort_by: str
    primary_edit: PrimaryEdit
    secondary_edits: Sequence[RangeEdit]
    doc: Optional[Doc]

