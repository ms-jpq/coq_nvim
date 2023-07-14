from .lsp.requests import completion, request, resolve
from .server.registrants import attachment, autocmds, help, marks, noop, omnifunc
from .server.registrants import preview as rp
from .server.registrants import repeat, snippets, stats, user_snippets

assert attachment
assert autocmds
assert completion
assert help
assert marks
assert noop
assert omnifunc
assert repeat
assert request
assert resolve
assert rp
assert snippets
assert stats
assert user_snippets

____ = None
