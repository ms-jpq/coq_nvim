from __future__ import annotations

from abc import abstractmethod
from dataclasses import dataclass
from enum import Enum, auto
from typing import (
    Annotated,
    Any,
    ClassVar,
    Literal,
    Optional,
    Protocol,
    Sequence,
    Type,
    TypeVar,
    runtime_checkable,
)

from .types import Completion, Context, ContextualEdit, MatchOptions, Snippet

"""
Newline seperated JSON RPC
"""


"""
Basic Layout
"""


@runtime_checkable
class HasID(Protocol):
    """
    ID must be unique between Request / Response pairs
    """

    @property
    @abstractmethod
    def uid(self) -> int:
        ...


@dataclass(frozen=True)
class _HasID(HasID):
    uid: int


@runtime_checkable
class Message(Protocol):
    """
    Messages are not ordered
    """

    @property
    @abstractmethod
    def m_type(self) -> Annotated[str, "Must be a Literal"]:
        ...


@runtime_checkable
class Notification(Message, Protocol):
    """
    Notifications can be ignored
    """


@runtime_checkable
class Response(Message, HasID, Protocol):
    """
    Each Request must receive a Response
    """


@runtime_checkable
class ErrorResponse(Response, Protocol):
    """
    Response Can be an Error
    """

    @property
    @abstractmethod
    def error(self) -> Literal[True]:
        ...

    @property
    @abstractmethod
    def msg(self) -> str:
        ...


@runtime_checkable
class Request(Message, HasID, Protocol):
    """
    Each Request type has a single vaild Response Type
    """

    resp_type: ClassVar[Type] = Response


"""
Authorship
"""


@runtime_checkable
class ClientSent(Message, Protocol):
    """
    Can only be sent from client
    """


@runtime_checkable
class ServerSent(Message, Protocol):
    """
    Can only be sent from server
    """


@runtime_checkable
class Broadcast(ServerSent, Protocol):
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
class DeadlinePastNotification(Broadcast, Notification):
    ctx_uid: int

    m_type: Literal["DeadlinePastNotification"] = "DeadlinePastNotification"


@dataclass(frozen=True)
class CompletionResponse(ClientSent, Response, _HasID):
    has_pending: bool
    completions: Sequence[Completion]

    m_type: Literal["CompletionResponse"] = "CompletionResponse"


@dataclass(frozen=True)
class CompletionRequest(Broadcast, Request, _HasID):
    deadline: Annotated[float, "Seconds since UNIX epoch"]
    context: Context

    m_type: Literal["CompletionRequest"] = "CompletionRequest"
    resp_type: ClassVar[Type[Message]] = CompletionResponse


@dataclass(frozen=True)
class FurtherCompletionRequest(ServerSent, Request, _HasID):
    deadline: Annotated[float, "Seconds since UNIX epoch"]
    ctx_uid: int

    m_type: Literal["FurtherCompletionRequest"] = "FurtherCompletionRequest"
    resp_type: ClassVar[Type[Message]] = CompletionResponse


"""
Snippet Request / Response
"""


@dataclass(frozen=True)
class _HasToken:
    completion_token: str


@dataclass(frozen=True)
class ParseResponse(ClientSent, Response, _HasToken, _HasID):
    edit: Optional[ContextualEdit]

    m_type: Literal["ParseResponse"] = "ParseResponse"


@dataclass(frozen=True)
class ParseRequest(Broadcast, Request, _HasID):
    snippet: Snippet

    m_type: Literal["ParseRequest"] = "ParseRequest"
    resp_type: ClassVar[Type[Message]] = ParseResponse


@dataclass(frozen=True)
class SnippetAppliedNotification(Broadcast, Notification, _HasToken):
    m_type: Literal["SnippetAppliedNotification"] = "SnippetAppliedNotification"
