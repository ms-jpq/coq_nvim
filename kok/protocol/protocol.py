from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import Annotated, ClassVar, Literal, Protocol, Type

"""
Newline seperated JSON RPC
"""


"""
Basic Layout
"""


@dataclass(frozen=True)
class Msg(Protocol):
    """
    Messages are not ordered
    """

    m_type: Annotated[str, "Must be a Literal"]
    uid: Annotated[int, "Must be unique between Request / Response"]


@dataclass(frozen=True)
class Response(Protocol):
    """
    Each Request must receive a Response
    """


@dataclass(frozen=True)
class Request(Protocol):
    """
    Each Request type has a single vaild Response Type
    """

    resp_type: ClassVar[Type] = Response


@dataclass(frozen=True)
class ClientSent(Protocol):
    """
    Can only be sent from client
    """


@dataclass(frozen=True)
class ServerSent(Msg, Protocol):
    """
    Can only be sent from server
    """


"""
Hand Shake
"""


class ConnectionType(Enum):
    """
    Enums are serialized by the name not value
    """

    unix = auto()
    tcp = auto()


@dataclass(frozen=True)
class ACK(ServerSent, Response):
    """
    Server must announce a connection mechanism
    """

    connection_type: ConnectionType
    address: str

    uid: Literal[0] = 0
    m_type: Literal["ACK"] = "ACK"


@dataclass(frozen=True)
class HELO(ClientSent, Request):
    """
    Client must make first request to server via Neovim's RPC mechaism
    """

    name: str
    short_name: str

    resp_type: ClassVar[Type] = ACK
    uid: Literal[0] = 0
    m_type: Literal["HELO"] = "HELO"


"""
"""


@dataclass(frozen=True)
class EditRequest:
    pass
