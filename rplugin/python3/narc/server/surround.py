from os.path import join, realpath

__base__ = join(realpath(__file__), "sql")

_INIT_ = join(__base__, "init.sql")
_PRAGMA_ = join(__base__, "pragma.sql")
_POP_ = join(__base__, "populate.sql")
