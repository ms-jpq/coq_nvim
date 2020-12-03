from inspect import getmembers, isfunction
from os.path import exists, join
from typing import Any, Callable, Iterator, Mapping, Optional, Sequence, Tuple

from ...clients import around, buffers, lsp, paths, tmux, tree_sitter
from ...shared.consts import load_hierarchy, module_entry_point
from ...shared.da import load_module
from ...shared.types import Seed, SourceChans, SnippetChans
from ..types import Settings


def load_extern(main_name: str) -> Optional[Callable[..., Any]]:
    for path in load_hierarchy:
        candidate = join(path, main_name)
        if exists(candidate):
            mod = load_module(candidate)
            for member_name, func in getmembers(mod, isfunction):
                if member_name == module_entry_point:
                    return func
    return None


def load_source() -> SourceChans:
    pass


def assemble(spec: SourceSpec, main: Factory, match: MatchOptions) -> SourceFactory:
    limit = spec.limit or inf
    rank = spec.rank or 100
    config = spec.config
    seed = Seed(
        match=match,
        limit=limit,
        config=config,
    )
    fact = SourceFactory(
        enabled=spec.enabled,
        short_name=spec.short_name,
        limit=limit,
        unique=spec.unique,
        rank=rank,
        seed=seed,
        manufacture=main,
    )
    return fact


def load_factories(settings: Settings) -> Mapping[str, SourceFactory]:
    def cont() -> Iterator[Tuple[str, SourceFactory]]:
        intrinsic: Mapping[str, Factory] = {
            around.NAME: around.main,
            buffers.NAME: buffers.main,
            lsp.NAME: lsp.main,
            paths.NAME: paths.main,
            tmux.NAME: tmux.main,
            tree_sitter.NAME: tree_sitter.main,
        }

        for name, main in intrinsic.items():
            spec = settings.sources[name]
            yield name, assemble(spec, main=main, match=settings.match)

        for name, spec in settings.sources.items():
            if name not in intrinsic:
                spec = settings.sources[name]
                main = load_external(spec.main)
                if main:
                    yield name, assemble(spec, main=main, match=settings.match)

    return {name: main for name, main in cont()}


def build(
    spec: SnippetEngineSpec, main: SnippetEngineFactory, match: MatchOptions
) -> EngineFactory:
    seed = SnippetSeed(config=spec.config, match=match)
    fact = EngineFactory(seed=seed, manufacture=main)
    return fact


def load_engines(settings: Settings) -> Mapping[str, EngineFactory]:
    def cont() -> Iterator[Tuple[Sequence[str], EngineFactory]]:
        intrinsic: Mapping[str, SnippetEngineFactory] = {}

        for name, main in intrinsic.items():
            spec = settings.snippet_engines[name]
            yield spec.kinds, build(spec, main=main, match=settings.match)

        for name, spec in settings.snippet_engines.items():
            if name not in intrinsic:
                spec = settings.snippet_engines[name]
                main = load_external(spec.main)
                if main:
                    yield spec.kinds, build(spec, main=main, match=settings.match)

    return {name: main for names, main in cont() for name in names}
