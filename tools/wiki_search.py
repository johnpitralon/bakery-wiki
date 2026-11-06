#!/usr/bin/env python3
"""BM25-like search over the wiki_index (fáze B).

Diagnosed weakness of the fáze D ripgrep baseline (see
wiki/concepts/Evaluace retrievalu nad wiki.md and tools/wiki-eval.py's
retrieve_ripgrep_baseline): it ranks by raw match count with no length
normalization, so a long, unrelated page that happens to mention a keyword
11 times beats a short, correct page that mentions it 8 times. BM25 fixes
exactly this — term frequency is saturating (diminishing returns per extra
occurrence) and normalized by document length relative to the corpus
average. No embeddings, no external dependencies, pure stdlib.

Retrieval unit: SECTIONS, not whole pages. Each heading's line range from
the index (tools/wiki_index.py) becomes one scorable "chunk", plus a
synthetic lead chunk per page for the text before the first heading (title +
frontmatter summary + intro). Scoring at section granularity is itself a
second length-normalization on top of BM25's own: a 30-section page no
longer "owns" all of its bulk against one relevant paragraph, because each
section competes as its own document. Page-level ranking then just takes
each page's best-scoring chunk — which is also why the mandatory
page-level recall metric in tools/wiki-eval.py doesn't need to change to see
this benefit (a better section match -> a lower hit_rank once ties are
broken by page id -> fewer whole unrelated pages counted in avg_tokens
ahead of it).

Field weighting (a practical, single-index approximation of BM25F): a
chunk's scored text is built by repeating its title / tags / heading with a
boost factor before handing it to plain BM25 — cheap, deterministic, no
extra data structures.

Graph expansion (B2b, toggleable): one hop only, not a transitive closure.
Given the primary ranked candidates, pull each candidate's direct link
neighbors (links_out ∪ links_in from the index) and let them compete via
max(their own BM25 score, a decayed score inherited from the seed that
linked to them). This mirrors how the vault is actually searched by a human
or an agent — incident -> entity -> concept -- and is expected to help most
on "vícekrokový" (multi-hop) questions, per the task brief.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass
from typing import Any

TOKEN_RE = re.compile(r"[\w\-]+", re.UNICODE)

# Mirrors tools/wiki-eval.py's STOPWORDS (kept in sync by hand, same
# rationale as that file's own comment: drop words that would match almost
# every page, not attempt real NLP).
STOPWORDS = {
    "a", "i", "o", "u", "v", "z", "s", "k", "na", "do", "se", "je", "jsou",
    "jak", "co", "kde", "kdy", "který", "která", "které", "kteří", "jaká",
    "jaké", "jaký", "jakou", "kolik", "proč", "aby", "ale", "ani", "ano",
    "byl", "byla", "bylo", "být", "dnes", "ten", "ta", "to", "tyto", "tato",
    "tohle", "ho", "ji", "jí", "jeho", "její", "jejich", "nebo", "než",
    "při", "pro", "před", "podle", "toho", "této", "tomu", "tom", "tím",
    "aby", "jen", "ještě", "už", "si", "svého", "své", "svou", "svých",
    "the", "for", "and", "with", "from", "that", "this",
}

# BM25 constants — standard defaults (Robertson/Sparck Jones).
K1 = 1.5
B = 0.75

# Field boosts: how many extra times a field's tokens are repeated before
# scoring, approximating BM25F without a separate per-field model.
TITLE_BOOST = 5
TAGS_BOOST = 4
HEADING_BOOST = 4
SUMMARY_BOOST = 2

# One-hop graph expansion: a neighbor's inherited score is this fraction of
# the seed page's own score, competing against the neighbor's own BM25 score
# (max of the two wins) — see module docstring.
GRAPH_DECAY = 0.6


def tokenize(text: str) -> list[str]:
    return [t.strip("-").lower() for t in TOKEN_RE.findall(text.lower()) if len(t.strip("-")) >= 2]


def _filtered(tokens: list[str]) -> list[str]:
    return [t for t in tokens if t not in STOPWORDS]


@dataclass
class Chunk:
    page_id: str
    heading: str | None  # None = lead chunk (before first heading)
    start_line: int
    end_line: int
    tokens: list[str]  # weighted, for BM25 scoring
    length: int = 0

    def __post_init__(self) -> None:
        self.length = len(self.tokens)


def _read_page_lines(wiki_root, rel_path: str) -> list[str]:
    return (wiki_root / rel_path).read_text(encoding="utf-8").splitlines()


def build_chunks(index: dict[str, dict[str, Any]], wiki_root) -> list[Chunk]:
    chunks: list[Chunk] = []
    for page_id, page in index.items():
        try:
            lines = _read_page_lines(wiki_root, page["path"])
        except OSError:
            continue
        title = page.get("title", "")
        tags_text = " ".join(page.get("tags", []))
        sections = page.get("sections", [])
        first_heading_line = sections[0]["start_line"] if sections else len(lines) + 1

        # Lead chunk: everything before the first heading (title, frontmatter
        # summary sentence, any intro prose) — carries the heaviest field
        # boosts since it IS the page's identity.
        lead_text_lines = lines[: first_heading_line - 1]
        lead_body = "\n".join(lead_text_lines)
        lead_tokens = (
            _filtered(tokenize(title)) * TITLE_BOOST
            + _filtered(tokenize(tags_text)) * TAGS_BOOST
            + _filtered(tokenize(page.get("summary", ""))) * SUMMARY_BOOST
            + _filtered(tokenize(lead_body))
        )
        if lead_tokens:
            chunks.append(
                Chunk(page_id=page_id, heading=None, start_line=1, end_line=max(first_heading_line - 1, 1), tokens=lead_tokens)
            )

        for section in sections:
            start, end = section["start_line"], section["end_line"]
            body = "\n".join(lines[start - 1 : end])
            tokens = (
                _filtered(tokenize(title)) * (TITLE_BOOST // 2)
                + _filtered(tokenize(tags_text)) * (TAGS_BOOST // 2)
                + _filtered(tokenize(section["heading"])) * HEADING_BOOST
                + _filtered(tokenize(body))
            )
            if tokens:
                chunks.append(Chunk(page_id=page_id, heading=section["heading"], start_line=start, end_line=end, tokens=tokens))

    if not chunks:
        chunks.append(Chunk(page_id="", heading=None, start_line=1, end_line=1, tokens=[]))
    return chunks


@dataclass
class BM25Index:
    chunks: list[Chunk]
    avgdl: float
    df: dict[str, int]
    n_docs: int

    def idf(self, term: str) -> float:
        n_t = self.df.get(term, 0)
        return math.log((self.n_docs - n_t + 0.5) / (n_t + 0.5) + 1.0)

    def score(self, chunk: Chunk, query_terms: list[str]) -> float:
        if not chunk.tokens:
            return 0.0
        freqs: dict[str, int] = {}
        for t in chunk.tokens:
            freqs[t] = freqs.get(t, 0) + 1
        score = 0.0
        dl = chunk.length
        for term in query_terms:
            f = freqs.get(term, 0)
            if f == 0:
                continue
            idf = self.idf(term)
            denom = f + K1 * (1 - B + B * dl / self.avgdl)
            score += idf * (f * (K1 + 1)) / denom
        return score


def build_bm25(chunks: list[Chunk]) -> BM25Index:
    n_docs = len(chunks)
    total_len = sum(c.length for c in chunks)
    avgdl = (total_len / n_docs) if n_docs else 1.0
    df: dict[str, int] = {}
    for c in chunks:
        for term in set(c.tokens):
            df[term] = df.get(term, 0) + 1
    return BM25Index(chunks=chunks, avgdl=avgdl or 1.0, df=df, n_docs=n_docs or 1)


@dataclass
class SearchHit:
    page_id: str
    path: str
    title: str
    heading: str | None
    start_line: int
    end_line: int
    score: float
    summary: str


def _best_chunk_per_page(scored: list[tuple[Chunk, float]]) -> dict[str, tuple[Chunk, float]]:
    best: dict[str, tuple[Chunk, float]] = {}
    for chunk, score in scored:
        if not chunk.page_id:
            continue
        current = best.get(chunk.page_id)
        if current is None or score > current[1]:
            best[chunk.page_id] = (chunk, score)
    return best


def search(
    index: dict[str, dict[str, Any]],
    wiki_root,
    query: str,
    top_k: int = 10,
    type_filter: str | None = None,
    graph_expand: bool = False,
    bm25: BM25Index | None = None,
    chunks: list[Chunk] | None = None,
) -> list[SearchHit]:
    """Rank pages by their best-matching section. bm25/chunks can be passed
    in pre-built (see build_search_state()) to avoid re-tokenizing the whole
    vault on every call — used by tools/wiki-eval.py, which calls this once
    per question."""
    if type_filter:
        candidate_pages = {pid for pid, p in index.items() if p.get("type") == type_filter}
    else:
        candidate_pages = set(index.keys())

    if chunks is None or bm25 is None:
        chunks = build_chunks(index, wiki_root)
        bm25 = build_bm25(chunks)

    query_terms = _filtered(tokenize(query))
    if not query_terms:
        return []

    scored = [(c, bm25.score(c, query_terms)) for c in bm25.chunks if c.page_id in candidate_pages]
    best_by_page = _best_chunk_per_page(scored)

    # Keep only pages with a nonzero own score for the primary ranking.
    ranked_ids = sorted(
        (pid for pid, (_, s) in best_by_page.items() if s > 0),
        key=lambda pid: (-best_by_page[pid][1], pid),
    )

    final_scores: dict[str, float] = {pid: best_by_page[pid][1] for pid in ranked_ids}

    if graph_expand and ranked_ids:
        seeds = ranked_ids[:top_k]
        for seed_id in seeds:
            seed_score = final_scores[seed_id]
            neighbors = set(index.get(seed_id, {}).get("links_out", [])) | set(index.get(seed_id, {}).get("links_in", []))
            for neighbor_id in neighbors:
                if neighbor_id not in candidate_pages or neighbor_id not in index:
                    continue
                propagated = GRAPH_DECAY * seed_score
                own = best_by_page.get(neighbor_id, (None, 0.0))[1]
                new_score = max(propagated, own)
                if new_score > final_scores.get(neighbor_id, 0.0):
                    final_scores[neighbor_id] = new_score
                if neighbor_id not in best_by_page:
                    # No chunk ever scored >0 for this neighbor — fabricate a
                    # display anchor: its lead chunk if one exists, else its
                    # first section, else the whole page.
                    neighbor_chunk = next((c for c, s in scored if c.page_id == neighbor_id and c.heading is None), None)
                    if neighbor_chunk is None:
                        neighbor_chunk = next((c for c, s in scored if c.page_id == neighbor_id), None)
                    if neighbor_chunk is None:
                        page = index[neighbor_id]
                        neighbor_chunk = Chunk(page_id=neighbor_id, heading=None, start_line=1, end_line=max(page.get("size_chars", 1), 1), tokens=[])
                    best_by_page[neighbor_id] = (neighbor_chunk, own)

    final_ids = sorted(final_scores.keys(), key=lambda pid: (-final_scores[pid], pid))[:top_k]

    hits: list[SearchHit] = []
    for pid in final_ids:
        chunk, _ = best_by_page[pid]
        page = index.get(pid, {})
        hits.append(
            SearchHit(
                page_id=pid,
                path=page.get("path", f"{pid}.md"),
                title=page.get("title", ""),
                heading=chunk.heading,
                start_line=chunk.start_line,
                end_line=chunk.end_line,
                score=final_scores[pid],
                summary=page.get("summary", ""),
            )
        )
    return hits


def build_search_state(index: dict[str, dict[str, Any]], wiki_root) -> tuple[BM25Index, list[Chunk]]:
    """Precompute chunks + BM25 stats once, for callers (wiki-eval.py) doing
    many queries against the same vault snapshot."""
    chunks = build_chunks(index, wiki_root)
    return build_bm25(chunks), chunks


def related(index: dict[str, dict[str, Any]], page_id: str) -> dict[str, list[dict[str, str]]]:
    page = index.get(page_id)
    if page is None:
        return {"links_out": [], "links_in": []}

    def _describe(pid: str) -> dict[str, str]:
        p = index.get(pid, {})
        return {"page_id": pid, "title": p.get("title", ""), "type": p.get("type", "")}

    return {
        "links_out": [_describe(pid) for pid in page.get("links_out", [])],
        "links_in": [_describe(pid) for pid in page.get("links_in", [])],
    }


def resolve_page_id(index: dict[str, dict[str, Any]], raw: str) -> str | None:
    """Lenient lookup for CLI args: accept with/without .md, with/without
    leading wiki/, or a bare page id."""
    candidate = raw.strip()
    if candidate.startswith("wiki/"):
        candidate = candidate[len("wiki/") :]
    if candidate.endswith(".md"):
        candidate = candidate[: -len(".md")]
    if candidate in index:
        return candidate
    # Fallback: match by basename, same as wikilink bare-name resolution.
    matches = [pid for pid in index if pid.rsplit("/", 1)[-1] == candidate.rsplit("/", 1)[-1]]
    if len(matches) == 1:
        return matches[0]
    return None


_ANCHOR_TICKS = re.compile(r"`")


def _normalize_heading(value: str) -> str:
    return _ANCHOR_TICKS.sub("", value).strip().lower()


def find_section(index: dict[str, dict[str, Any]], page_id: str, heading: str) -> tuple[dict[str, Any] | None, list[str]]:
    """Returns (section, candidate_headings). section is the unique match,
    or None when there is no match or more than one (ambiguous) — in either
    failure case candidate_headings lists what the caller can report:
    the ambiguous matches themselves, or (if nothing matched at all) every
    heading on the page, so the CLI can say "did you mean one of these"."""
    page = index.get(page_id)
    if page is None:
        return None, []
    sections = page.get("sections", [])
    all_headings = [s["heading"] for s in sections]
    target_norm = _normalize_heading(heading)
    exact = [s for s in sections if _normalize_heading(s["heading"]) == target_norm]
    if len(exact) == 1:
        return exact[0], []
    if len(exact) > 1:
        return None, [s["heading"] for s in exact]
    contains = [s for s in sections if target_norm in _normalize_heading(s["heading"])]
    if len(contains) == 1:
        return contains[0], []
    if len(contains) > 1:
        return None, [s["heading"] for s in contains]
    return None, all_headings
