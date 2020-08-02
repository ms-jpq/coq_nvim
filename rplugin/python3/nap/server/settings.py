from inspect import getmembers, isfunction
from math import inf
from os.path import exists, join
from typing import Any, Callable, Dict, Iterator, Optional, Sequence, Tuple

from ..clients import around, buffers, lsp, paths, tmux, tree_sitter
from ..shared.da import load_json, load_module, merge_all
from ..shared.types import Factory, Seed, SnippetEngineFactory, SnippetSeed
from ..snippets.lsp import main as lsp_snippet
from .consts import load_hierarchy, module_entry_point, settings_json
from .types import (
    CacheOptions,
    EngineFactory,
    MatchOptions,
    Settings,
    SnippetEngineSpec,
    SourceFactory,
    SourceSpec,
)


def load_source(config: Dict[str, Any]) -> SourceSpec:
    spec = SourceSpec(
        main=config["main"],
        enabled=config["enabled"],
        short_name=config["short_name"],
        limit=config.get("limit"),
        timeout=config.get("timeout"),
        rank=config.get("rank"),
        config=config.get("config") or {},
    )
    return spec


def load_engine(config: Dict[str, Any]) -> SnippetEngineSpec:
    spec = SnippetEngineSpec(
        main=config["main"],
        enabled=config["enabled"],
        kind=config["kind"],
        config=config.get("config") or {},
    )
    return spec


def initial(configs: Sequence[Any]) -> Settings:
    config = merge_all(load_json(settings_json), *configs, replace=True)
    match_o = config["match"]
    cache_o = config["cache"]
    match = MatchOptions(
        min_match=match_o["min_match"], unifying_chars={*match_o["unifying_chars"]}
    )
    cache = CacheOptions(
        short_name=cache_o["short_name"],
        band_size=cache_o["band_size"],
        limit=cache_o["limit"],
    )
    sources = {name: load_source(conf) for name, conf in config["sources"].items()}
    snippet_engines = {
        name: load_engine(conf) for name, conf in config["snippet_engines"].items()
    }
    settings = Settings(
        match=match, cache=cache, sources=sources, snippet_engines=snippet_engines
    )
    return settings


def load_external(main_name: str) -> Optional[Callable[..., Any]]:
    for path in load_hierarchy:
        candidate = join(path, main_name)
        if exists(candidate):
            mod = load_module(candidate)
            for member_name, func in getmembers(mod, isfunction):
                if member_name == module_entry_point:
                    return func
    return None


def assemble(spec: SourceSpec, main: Factory, match: MatchOptions,) -> SourceFactory:
    limit = spec.limit or inf
    timeout = (spec.timeout or inf) / 1000
    rank = spec.rank or 100
    config = spec.config
    seed = Seed(match=match, limit=limit, timeout=timeout, config=config,)
    fact = SourceFactory(
        short_name=spec.short_name,
        limit=limit,
        timeout=timeout,
        rank=rank,
        seed=seed,
        manufacture=main,
    )
    return fact


def load_factories(settings: Settings) -> Dict[str, SourceFactory]:
    def cont() -> Iterator[Tuple[str, SourceFactory]]:
        intrinsic = {
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

    return {n: f for n, f in cont()}


def build(
    spec: SnippetEngineSpec, main: SnippetEngineFactory
) -> EngineFactory:
    seed = SnippetSeed(config=spec.config)
    fact = EngineFactory(seed=seed, manufacture=main)
    return fact


def load_engines(settings: Settings) -> Dict[str, EngineFactory]:
    def cont() -> Iterator[Tuple[str, EngineFactory]]:
        intrinsic = {
            lsp_snippet.NAME: lsp_snippet.main,
        }

        for name, main in intrinsic.items():
            spec = settings.snippet_engines[name]
            yield spec.kind, build(spec, main=main)

        for name, spec in settings.snippet_engines.items():
            if name not in intrinsic:
                spec = settings.snippet_engines[name]
                main = load_external(spec.main)
                if main:
                    yield spec.kind, build(spec, main=main)

    return {n: f for n, f in cont()}
