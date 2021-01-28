from difflib import SequenceMatcher
from math import inf
from typing import Dict

from ...shared.parse import is_word
from ...shared.protocol.types import Context, Options
from .types import Metric

#     matches: Mapping[int, str]
#     full_match: bool


def _isjunk(s: str) -> bool:
    return s.isspace()


def gen_metric_secondary(ncword: str, n_match: str) -> Metric:
    m = SequenceMatcher(a=ncword, b=n_match, autojunk=True, isjunk=_isjunk)
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
    options: Options,
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


def gen_metric_wrap(
    context: Context, suggestion: Suggestion, options: Options, use_secondary: bool
) -> Metric:
    match, n_match = suggestion.match, suggestion.match_normalized
    word_start = is_word(match[:1], unifying_chars=options.unifying_chars)
    cword, ncword = (
        (context.alnums, context.alnums_normalized)
        if word_start
        else (context.alnum_syms, context.alnum_syms_normalized)
    )

    metric = gen_metric(
        cword,
        ncword=ncword,
        match=match,
        n_match=n_match,
        options=options,
        use_secondary=use_secondary,
    )
    return metric
