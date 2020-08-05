from dataclasses import dataclass
from difflib import SequenceMatcher
from math import inf
from typing import Dict, Iterator

from .types import MatchOptions


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float
    matches: Dict[int, str]


def gen_metric_secondary(ncword: str, n_match: str) -> Metric:
    m = SequenceMatcher(a=ncword, b=n_match)
    matches: Dict[int, str] = {}
    prefix_matches = 0
    num_matches = 0
    consecutive_matches = 0

    metric = Metric(
        prefix_matches=prefix_matches,
        num_matches=num_matches,
        consecutive_matches=consecutive_matches,
        density=m.ratio(),
        matches=matches,
    )

    return metric


def gen_metric(
    cword: str, ncword: str, match: str, n_match: str, options: MatchOptions
) -> Metric:
    matches: Dict[int, str] = {}

    idx = 0
    prefix_broken = False
    pm_idx = inf
    prefix_matches = 0
    consecutive_matches = 0
    for i, char in enumerate(cword):
        target = match if char.isupper() else n_match
        m_idx = target.find(char, idx, idx + options.transpose_band)
        if m_idx != -1:
            if pm_idx == m_idx - 1:
                consecutive_matches += 1
            pm_idx = m_idx
            matches[m_idx] = char
            idx = m_idx + 1
        if m_idx != i:
            prefix_broken = True
        if not prefix_broken:
            prefix_matches += 1

    num_matches = len(matches)
    density = num_matches / len(match) if match else 0
    metric = Metric(
        prefix_matches=prefix_matches,
        num_matches=num_matches,
        consecutive_matches=consecutive_matches,
        density=density,
        matches=matches,
    )

    return metric


def find_matches(
    cword: str,
    ncword: str,
    min_match: int,
    words: Dict[str, str],
    options: MatchOptions,
) -> Iterator[str]:
    for match, n_match in words.items():
        if n_match not in ncword:
            metric = gen_metric(
                cword, ncword=ncword, match=match, n_match=n_match, options=options
            )
            if metric.num_matches >= min_match:
                yield match
