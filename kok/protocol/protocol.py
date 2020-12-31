from __future__ import annotations

from dataclasses import dataclass
from enum import Enum, auto
from typing import Annotated, ClassVar, Literal, Optional, Protocol, Sequence, Type

from .types import Completion, Context, ContextualEdit, MatchOptions, Snippet

"""
Newline seperated JSON RPC
"""


"""
Basic Layout
"""


class HasID(Protocol):
    """
    ID must be unique between Request / Response pairs
    """

    @property
    def uid(self) -> int:
        ...


@dataclass(frozen=True)
class _HasID(HasID):
    uid: int


class Message(HasID, Protocol):
    """
    Messages are not ordered
    """

    @property
    def m_type(self) -> Annotated[str, "Must be a Literal"]:
        ...


class Response(Message, Protocol):
    """
    Each Request must receive a Response
    """


class Request(Message, Protocol):
    """
    Each Request type has a single vaild Response Type
    """

    resp_type: ClassVar[Type] = Response


class ClientSent(Message, Protocol):
    """
    Can only be sent from client
    """


class ServerSent(Message, Protocol):
    """
    Can only be sent from server
    """


class Broadcast(ServerSent, Request, Protocol):
    """
    Sent to all clients
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
    options: MatchOptions

    uid: Literal[0] = 0
    m_type: Literal["ACK"] = "ACK"


@dataclass(frozen=True)
class Hello(ClientSent, Request):
    """
    Client must make first request to server via Neovim's RPC mechaism
    """

    name: str
    short_name: str

    uid: Literal[0] = 0
    m_type: Literal["HELO"] = "HELO"
    resp_type: ClassVar[Type[Message]] = Acknowledge


"""
Completion Request / Response
"""


@dataclass(frozen=True)
class CompletionResponse(ClientSent, Response, _HasID):
    has_pending: bool
    completions: Sequence[Completion]

    m_type: Literal["CompletionResponse"] = "CompletionResponse"


@dataclass(frozen=True)
class CompletionRequest(Broadcast, _HasID):
    deadline: Annotated[float, "Seconds since UNIX epoch"]
    context: Context

    m_type: Literal["CompletionRequest"] = "CompletionRequest"
    resp_type: ClassVar[Type[Message]] = CompletionResponse


@dataclass(frozen=True)
class FurtherCompletionRequest(Broadcast, _HasID):
    deadline: Annotated[float, "Seconds since UNIX epoch"]
    parent_uid: Annotated[int, "UID of parent Response"]

    m_type: Literal["FurtherCompletionRequest"] = "FurtherCompletionRequest"
    resp_type: ClassVar[Type[Message]] = CompletionResponse


"""
Snippet Request / Response
"""


@dataclass(frozen=True)
class ParseResponse(ClientSent, Response, _HasID):
    edit: Optional[ContextualEdit]

    m_type: Literal["ParseResponse"] = "ParseResponse"


@dataclass(frozen=True)
class ParseRequest(Broadcast, _HasID):
    snippet: Snippet

    m_type: Literal["ParseRequest"] = "ParseRequest"
