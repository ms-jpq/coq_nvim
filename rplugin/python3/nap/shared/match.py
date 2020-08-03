from dataclasses import dataclass
from math import inf
from typing import Dict


@dataclass(frozen=True)
class Metric:
    prefix_matches: int
    consecutive_matches: int
    num_matches: int
    density: float
    matches: Dict[int, str]


def gen_metric(cword: str, match: str, match_normalized: str, transpose_band: int) -> Metric:
    matches: Dict[int, str] = {}

    idx = 0
    prefix_broken = False
    pm_idx = inf
    prefix_matches = 0
    consecutive_matches = 0
    for i, char in enumerate(cword):
        target = match if char.isupper() else match_normalized
        m_idx = target.find(char, idx, idx + transpose_band)
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
