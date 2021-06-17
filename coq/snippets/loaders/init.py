from dataclasses import dataclass
from itertools import  product
from os import walk
from os.path import basename, join, splitext
from typing import (
    Any,
    Callable,
    List,
    MutableMapping,
    MutableSequence,
    Sequence,
    Set,
    Tuple,
    Mapping,
    cast,
    AbstractSet
)


from .lsp import SNIPPET_DISPLAY as L_SNIPPET_DISPLAY
from .lsp import SNIPPET_KIND as L_SNIPPET_KIND
from .lsp import parse_one as parse_one_lsp
from .neosnippet import SNIPPET_DISPLAY as N_SNIPPET_DISPLAY
from .neosnippet import SNIPPET_KIND as N_SNIPPET_KIND
from .neosnippet import parse_one as parse_one_neosnippet
from .types import LoadError, LoadSingle, MetaSnippet, Options
from .snipmate import SNIPPET_DISPLAY as S_SNIPPET_DISPLAY
from .snipmate import SNIPPET_KIND as S_SNIPPET_KIND
from .snipmate import parse_one as parse_one_snipmate
from .ultisnip import SNIPPET_DISPLAY as U_SNIPPET_DISPLAY
from .ultisnip import SNIPPET_KIND as U_SNIPPET_KIND
from .ultisnip import parse_one as parse_one_ultisnip

_ResolvedPaths = MutableMapping[str, List[str]]
_ParseOne = Callable[[str], Tuple[Sequence[MetaSnippet], Sequence[str]]]


@dataclass(frozen=True)
class L2:
    kind_idx: int
    resolved_paths: _ResolvedPaths
    parser: _ParseOne


def load_paths(paths: Sequence[Path], exts: Set[str]) -> Mapping[str, Sequence[str]]:
    path_resolved: MutableMapping[str, Sequence[str]] = {}

    for prefix, path in product(__search_paths__, paths):
        p = join(prefix, path)
        for (
            root,
            _,
            files,
        ) in walk(p, followlinks=True):
            for file in files:
                full_name = join(root, file)
                filetype, ext = splitext(basename(full_name))
                if ext in exts:
                    coll = path_resolved.setdefault(filetype, [])
                    coll.append(full_name)

    return path_resolved


def parse_many(
    filetype: str, arg: L2
) -> Tuple[int, Sequence[MetaSnippet], Sequence[str]]:
    async def p1(path: str) -> LoadSingle:
        try:
            parser = cast(_ParseOne, arg.parser)  # type: ignore
            return await run_in_executor(parser, path)
        except LoadError as e:
            log.exception("%s", e)
            return (), ()

    paths = arg.resolved_paths.get(filetype)
    if paths:
        loaded = await gather(*(p1(path) for path in paths))
        snips, exts = zip(*loaded)
        snippets = tuple(s for snip in snips for s in snip)
        extensions = tuple(e for ext in exts for e in ext)
        return (
            arg.kind_idx,
            cast(Sequence[MetaSnippet], snippets),
            cast(Sequence[str], extensions),
        )
    else:
        return arg.kind_idx, (), ()


def load_filetype(

    filetype: str,
    options: Dict[Options, int],
    args: Sequence[L2],
) -> int:
    fti = await query_filetype(conn, filetype=filetype)

    if fti is not None:
        return fti
    else:
        ft_idx = await init_filetype(conn, filetype=filetype)

        parsed = await gather(*(parse_many(filetype=filetype, arg=arg) for arg in args))
        zipped = zip(*parsed)
        _, _, raw_exts = cast(Any, zipped)
        exts = {*raw_exts}

        extensions = await gather(
            *(
                load_filetype(conn, filetype=ft, options=options, args=args)
                for ext in exts
                for ft in ext
            )
        )

        await init_extensions(conn, dest=ft_idx, srcs=extensions)
        for kind_idx, snips, _ in parsed:
            await populate(
                conn,
                kind_idx=kind_idx,
                ft_idx=ft_idx,
                options=options,
                snips=snips,
            )

        log.debug("%s", f"Loaded: {filetype}")
        return ft_idx


async def gen_l2(
    conn: AConnection,
    parser: _ParseOne,
    paths: Sequence[str],
    kind: str,
    kind_name: str,
    exts: Set[str],
) -> L2:
    resolved_paths, kind_idx = await gather(
        load_paths(paths, exts=exts),
        init_snippet_kind(conn, kind=kind, display=kind_name),
    )
    l2 = L2(kind_idx=kind_idx, resolved_paths=resolved_paths, parser=parser)
    return l2


def load_all(
    lsp: Sequence[str],
    snipmate: Sequence[str],
    neosnippet: Sequence[str],
    ultisnips: Sequence[str],
    ) -> None:

    l2s = await gather(
        gen_l2(
            conn,
            parser=parse_one,
            paths=lsp,
            kind=L_SNIPPET_KIND,
            kind_name=L_SNIPPET_DISPLAY,
            exts={".json"},
        ),
        gen_l2(
            conn,
            parser=parse_one,
            paths=snipmate,
            kind=S_SNIPPET_KIND,
            kind_name=S_SNIPPET_DISPLAY,
            exts={".snippets", ".snip"},
        ),
        gen_l2(
            conn,
            parser=parse_one,
            paths=neosnippet,
            kind=N_SNIPPET_KIND,
            kind_name=N_SNIPPET_DISPLAY,
            exts={".snippets", ".snip"},
        ),
        gen_l2(
            conn,
            parser=_parse_one,
            paths=ultisnips,
            kind=U_SNIPPET_KIND,
            kind_name=U_SNIPPET_DISPLAY,
            exts={".snippets", ".snip"},
        ),
    )

    fut: Future = Future()
    keys = {filetype for l2 in l2s for filetype in l2.resolved_paths}

