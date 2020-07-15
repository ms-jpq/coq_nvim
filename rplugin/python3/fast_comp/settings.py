from inspect import getmembers, isfunction
from os.path import exists, join
from typing import Any, Iterator

from .consts import load_hierarchy, module_entry_point, settings_json
from .da import load_json, load_module
from .types import Settings, SourceFactory, SourceSpec


def load_source(config: Any) -> SourceSpec:
    spec = SourceSpec(
        main=config["main"],
        enabled=config["enabled"],
        priority=config["priority"],
        short=config["short"],
        config=config["config"],
    )
    return spec


def initial() -> Settings:
    config = load_json(settings_json)
    sources = {name: load_source(conf) for name, conf in config["sources"]}
    settings = Settings(sources=sources)
    return settings


def load_factories(settings: Settings) -> Iterator[SourceFactory]:
    for name, spec in settings.sources.items():
        for path in load_hierarchy:
            candidate = join(path, spec.main)
            if exists(candidate):
                mod = load_module(candidate)
                for name, func in getmembers(mod, isfunction):
                    if name == module_entry_point:
                        fact = SourceFactory(
                            name=name,
                            short_name=spec.short_name,
                            priority=spec.priority,
                            timeout=spec.timeout,
                        )
                        yield fact
