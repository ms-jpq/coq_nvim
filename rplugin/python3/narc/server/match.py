from dataclasses import dataclass
from difflib import SequenceMatcher
from math import inf
from typing import Dict

from .types import MatchOptions


@dataclass(frozen=True)
class MetricSeed:
    cword: str
    ncword: str
    match: str
    n_match: str
    options: MatchOptions
    use_secondary: bool


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float
    matches: Dict[int, str]
    full_match: bool


def isjunk(s: str) -> bool:
    return s.isspace()


def gen_metric_secondary(ncword: str, n_match: str) -> Metric:
    m = SequenceMatcher(a=ncword, b=n_match, autojunk=True, isjunk=isjunk)
    matches: Dict[int, str] = {}
    prefix_matches = 0
    num_matches = 0
    consecutive_matches = 0

    for ai, bi, size in m.get_matching_blocks():
        num_matches += size
        if ai == bi == 0:
            prefix_matches = size
        for i in range(bi, bi + size):
            matches[i] = n_match[i]

    pm_idx = inf
    for i in sorted(matches):
        if pm_idx == i - 1:
            consecutive_matches += 1
        pm_idx = i

    density = num_matches / len(n_match) if n_match else 0
    full_match = prefix_matches == len(ncword)
    metric = Metric(
        prefix_matches=prefix_matches,
        num_matches=num_matches,
        consecutive_matches=consecutive_matches,
        density=density,
        matches=matches,
        full_match=full_match,
    )
    return metric


def gen_metric(
    cword: str,
    ncword: str,
    match: str,
    n_match: str,
    options: MatchOptions,
    use_secondary: bool,
) -> Metric:
    transband = options.transpose_band
    matches: Dict[int, str] = {}

    idx = 0
    prefix_broken = False
    pm_idx = inf
    prefix_matches = 0
    consecutive_matches = 0
    num_matches = 0
    for i, char in enumerate(cword):
        if use_secondary and i > transband and not num_matches:
            return gen_metric_secondary(ncword, n_match=n_match)
        target = match if char.isupper() else n_match
        m_idx = target.find(char, idx, idx + transband)
        if m_idx != -1:
            if pm_idx == m_idx - 1:
                consecutive_matches += 1
            num_matches += 1
            matches[m_idx] = char
            pm_idx = m_idx
            idx = m_idx + 1
        if m_idx != i:
            prefix_broken = True
        if not prefix_broken:
            prefix_matches += 1

    density = num_matches / len(match) if match else 0
    full_match = prefix_matches == len(ncword)
    metric = Metric(
        prefix_matches=prefix_matches,
        num_matches=num_matches,
        consecutive_matches=consecutive_matches,
        density=density,
        matches=matches,
        full_match=full_match,
    )
    return metric
