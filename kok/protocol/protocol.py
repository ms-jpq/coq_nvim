from typing import Literal, Protocol, Annotated

from dataclasses import dataclass


@dataclass(frozen=True)
class Msg(Protocol):
    m_type: Annotated[str, "Must be a Literal"]
    uid: Annotated[int, "Must be unique between Req / Reply"]


@dataclass(frozen=True)
class ClientMsg(Msg, Protocol):
    """
    Can only be sent from client
    """
    m_type: Literal["ClientMsg"]


@dataclass(frozen=True)
class ServerMsg(Msg, Protocol):
    m_type: Literal["ServerMsg"]


@dataclass(frozen=True)
class Msg(Protocol):
    m_type: str
    uid: int


@dataclass(frozen=True)
class HELO(Msg):
    m_type: Literal["HELO"]
    uid: Literal[0]


@dataclass(frozen=True)
class ACK(Msg):
    m_type: Literal["ACK"]
    uid: Literal[0]


@dataclass(frozen=True)
class EditRequest:
    pass
