from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import Annotated, ClassVar, Literal, Protocol, Type

from .types import Context

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
class ServerSent(Protocol):
    """
    Can only be sent from server
    """


"""
Hand Shake
"""


class ConnectionType(Enum):
    """
    Enums are serialized by name not value
    """

    unix = auto()
    tcp = auto()


@dataclass(frozen=True)
class Acknowledge(ServerSent, Response):
    """
    Server must announce a connection mechanism
    """

    connection_type: ConnectionType
    address: str

    uid: Literal[0] = 0
    m_type: Literal["ACK"] = "ACK"


@dataclass(frozen=True)
class Hello(ClientSent, Request):
    """
    Client must make first request to server via Neovim's RPC mechaism
    """

    name: str
    short_name: str

    resp_type: ClassVar[Type] = Acknowledge
    uid: Literal[0] = 0
    m_type: Literal["HELO"] = "HELO"


"""
After Handshake
"""

"""
Except for Handshake
"""


@dataclass(frozen=True)
class CompletionResponse(ClientSent, Response):
    complete: Annotated[bool, ""]


@dataclass(frozen=True)
class CompletionRequest(ClientSent, Request):
    deadline: Annotated[float, "Seconds since 1970"]

    context: Context
    pass


@dataclass(frozen=True)
class EditRequest(ClientSent, Request):
    pass
