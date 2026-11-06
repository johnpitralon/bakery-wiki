#!/usr/bin/env python3
"""Wiki index builder + cache for bakery-wiki (fáze B, navigační vrstva).

A page-level index is not enough for an agent to read *sections* instead of
whole files — that requires knowing, ahead of time, which line ranges belong
to which heading, plus enough metadata (tags, summary, link graph) to score
and rank without re-reading every file on every query. This module builds
exactly that: for every wiki/**/*.md page — path, title, type, tags,
created/updated, size in characters, a list of headings with line ranges,
outbound/inbound `[[links]]`, and a one-sentence summary (the first
paragraph under frontmatter, per Kytary.Wiki wiki/CONVENTIONS.md (upstream) page structure).

CRITICAL — this index is a derived, machine-only cache. It must NEVER be
committed (see repo .gitignore) and staleness must be structurally
impossible, not just discouraged: every call to load_or_build() re-scans
(size, mtime_ns) for every wiki/**/*.md file and compares that manifest
against what's stored in the cache. Any mismatch — a changed file, a new
file, a deleted file — forces a full rebuild before returning. Nothing here
depends on a human or a hook remembering to regenerate anything.

Why the paranoia in the docstring above: an opt-in local hook (like
tools/bakery-sync's) can be missing and the only visible symptom is a commit
that should have been blocked going through anyway — a human eventually
notices a bad commit. A silently stale *cache* has no equivalent tell: the
agent just answers confidently from data that no longer matches the vault.
See .githooks/pre-commit's own documented case of a validator that didn't
block for three months unnoticed — the failure mode this design refuses to
repeat for a cache with no validator watching it at all.

No external dependencies, deterministic output (no wall-clock data baked
into the index itself — only content-derived facts), pure Python 3 stdlib.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path, PurePosixPath
from typing import Any

CACHE_VERSION = 3

WIKILINK = re.compile(r"\[\[([^\]\n]+)\]\]")
HEADING_RE = re.compile(r"^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$")

# Mirrors tools/wiki-integrity-check.py's FOLDER_PRECEDENCE — kept in sync by
# hand (see that file's own comment) because this module intentionally does
# not import it (hyphenated filename, and the checker's Page dataclass
# carries more than this index needs). Used only to resolve a *bare*
# `[[Name]]` link deterministically when the basename exists in more than
# one top-level folder.
FOLDER_PRECEDENCE = ("entities", "concepts", "domains", "", "changelog", "incidents")


# --------------------------------------------------------------------------
# Frontmatter + markdown parsing (small, self-contained — see module
# docstring for why this isn't shared code with wiki-integrity-check.py /
# wiki-eval.py: each tool in tools/ parses independently, no external deps,
# no intra-tool import coupling).
# --------------------------------------------------------------------------


def parse_frontmatter(lines: list[str]) -> tuple[dict[str, str], int]:
    """Returns (metadata, end_index) where end_index is the 0-based line
    index of the closing '---' (or 0 if there is no valid frontmatter)."""
    if not lines or lines[0] != "---":
        return {}, 0
    try:
        end = lines.index("---", 1)
    except ValueError:
        return {}, 0
    metadata: dict[str, str] = {}
    for line in lines[1:end]:
        if not line or line.lstrip().startswith("#") or line[:1].isspace():
            continue
        if ":" not in line:
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if key:
            metadata[key] = value
    return metadata, end


def parse_tags(raw: str | None) -> list[str]:
    if not raw:
        return []
    raw = raw.strip()
    if raw.startswith("[") and raw.endswith("]"):
        raw = raw[1:-1]
    tags = []
    for part in raw.split(","):
        part = part.strip()
        if len(part) >= 2 and part[0] == part[-1] and part[0] in "\"'":
            part = part[1:-1]
        if part:
            tags.append(part)
    return tags


def extract_summary(lines: list[str], body_start: int) -> str:
    """First paragraph after frontmatter — Kytary.Wiki wiki/CONVENTIONS.md (upstream) requires every
    page to open with a 2-3 sentence overview, no heading, right under the
    frontmatter block. Stops at the first blank line or heading."""
    collected: list[str] = []
    for line in lines[body_start:]:
        stripped = line.strip()
        if not stripped:
            if collected:
                break
            continue
        if HEADING_RE.match(line):
            break
        collected.append(stripped)
    return " ".join(collected).strip()


def extract_sections(lines: list[str]) -> list[dict[str, Any]]:
    """One entry per heading: level, 1-indexed start_line (the heading line
    itself) and end_line (inclusive — the line right before the next heading
    of the same or shallower level, or EOF). A section's range therefore
    includes its own subsections, matching how a person would read "the
    section" if asked to open it."""
    headings: list[tuple[int, int, str]] = []
    for i, line in enumerate(lines, start=1):
        m = HEADING_RE.match(line)
        if m:
            headings.append((i, len(m.group(1)), m.group(2).strip()))
    sections = []
    for idx, (line_no, level, text) in enumerate(headings):
        end = len(lines)
        for later_no, later_level, _ in headings[idx + 1 :]:
            if later_level <= level:
                end = later_no - 1
                break
        sections.append({"heading": text, "level": level, "start_line": line_no, "end_line": end})
    return sections


def scannable_lines(lines: list[str]) -> list[tuple[int, str]]:
    """Line numbers + text, skipping fenced code blocks — same convention as
    wiki-integrity-check.py's scannable_lines(), so link extraction doesn't
    pick up `[[example]]` inside a ```code fence```."""
    result: list[tuple[int, str]] = []
    in_fence = False
    for line_number, line in enumerate(lines, start=1):
        if line.strip().startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        result.append((line_number, line))
    return result


def _wikilink_in_inline_code(line: str, start: int, end: int) -> bool:
    index = 0
    while index < len(line):
        if line[index] != "`":
            index += 1
            continue
        closing = line.find("`", index + 1)
        if closing == -1:
            break
        if start >= index and end <= closing + 1:
            return True
        index = closing + 1
    return False


def _split_link(value: str) -> str:
    target = value.replace("\\|", "|").split("|", 1)[0].strip()
    if target.startswith("#"):
        return ""
    return target.split("#", 1)[0].strip()


def _normalized_rel(value: str) -> str:
    parts: list[str] = []
    for part in PurePosixPath(value).parts:
        if part in ("", "."):
            continue
        if part == "..":
            if parts:
                parts.pop()
            continue
        parts.append(part)
    return "/".join(parts)


def _expand_candidates(source_rel: str, target: str) -> list[str]:
    candidates: list[str] = []
    if target.startswith(("./", "../")):
        candidates.append(_normalized_rel(f"{PurePosixPath(source_rel).parent}/{target}"))
        if target.startswith("../wiki/"):
            candidates.append(_normalized_rel(target.removeprefix("../wiki/")))
    else:
        candidates.append(_normalized_rel(target.removeprefix("wiki/")))
    expanded: list[str] = []
    for c in candidates:
        expanded.append(c)
        if c.startswith("wiki/"):
            expanded.append(c.removeprefix("wiki/"))
    return expanded


def _resolve_bare_target(target: str, titles: dict[str, str]) -> str | None:
    matches = [rel for rel, title in titles.items() if rel[:-3] == target or Path(rel).stem == target or title == target]
    if not matches:
        return None
    if len(matches) == 1:
        return matches[0]
    by_folder: dict[str, list[str]] = {}
    for rel in matches:
        parts = PurePosixPath(rel).parts
        folder = parts[0] if len(parts) > 1 else ""
        by_folder.setdefault(folder, []).append(rel)
    for folder in FOLDER_PRECEDENCE:
        candidates = by_folder.get(folder)
        if candidates:
            return sorted(candidates)[0]
    return sorted(matches)[0]


def _resolve_target(source_rel: str, target: str, titles: dict[str, str]) -> str | None:
    target = target.strip()
    if target.endswith(".md"):
        target = target[:-3]
    if not target:
        return source_rel
    for candidate in _expand_candidates(source_rel, target):
        full = f"{candidate}.md"
        if full in titles:
            return full
    return _resolve_bare_target(target, titles)


# --------------------------------------------------------------------------
# Index build
# --------------------------------------------------------------------------


@dataclass
class RawPage:
    rel: str  # e.g. "entities/ai-radio.md"
    lines: list[str]
    metadata: dict[str, str]
    body_start: int


def _read_pages(wiki_root: Path) -> dict[str, RawPage]:
    pages: dict[str, RawPage] = {}
    for path in sorted(wiki_root.rglob("*.md")):
        rel = path.relative_to(wiki_root).as_posix()
        text = path.read_text(encoding="utf-8")
        lines = text.splitlines()
        metadata, end = parse_frontmatter(lines)
        pages[rel] = RawPage(rel=rel, lines=lines, metadata=metadata, body_start=end + 1 if end else 0)
    return pages


def build_index(wiki_root: Path) -> dict[str, dict[str, Any]]:
    """Build the full page index. Returns {page_id: page_dict}, page_id being
    the rel path without ".md" — same convention [[wiki-links]] and
    tools/wiki-eval.py use."""
    raw_pages = _read_pages(wiki_root)
    titles = {rel: page.metadata.get("title", "") for rel, page in raw_pages.items()}

    index: dict[str, dict[str, Any]] = {}
    for rel, page in raw_pages.items():
        page_id = rel[:-3]
        full_text = "\n".join(page.lines)
        links_out: set[str] = set()
        for _, line in scannable_lines(page.lines):
            for match in WIKILINK.finditer(line):
                if _wikilink_in_inline_code(line, match.start(), match.end()):
                    continue
                target = _split_link(match.group(1))
                if not target:
                    continue
                resolved = _resolve_target(rel, target, titles)
                if resolved and resolved != rel:
                    links_out.add(resolved[:-3])

        index[page_id] = {
            "path": rel,
            "title": page.metadata.get("title", ""),
            "type": page.metadata.get("type", ""),
            "tags": parse_tags(page.metadata.get("tags")),
            "created": page.metadata.get("created", ""),
            "updated": page.metadata.get("updated", ""),
            "size_chars": len(full_text),
            "summary": extract_summary(page.lines, page.body_start),
            "sections": extract_sections(page.lines),
            "links_out": sorted(links_out),
            "links_in": [],  # filled below
        }

    links_in: dict[str, set[str]] = {pid: set() for pid in index}
    for pid, page in index.items():
        for target in page["links_out"]:
            if target in links_in:
                links_in[target].add(pid)
    for pid, sources in links_in.items():
        index[pid]["links_in"] = sorted(sources)

    return index


# --------------------------------------------------------------------------
# Cache — manifest-checked, never trusted blindly
# --------------------------------------------------------------------------


def default_cache_path(wiki_root: Path) -> Path:
    """wiki_root is the wiki/ directory; the cache lives as a sibling under
    <repo_root>/.cache/, gitignored (see .gitignore: `/.cache/`)."""
    return wiki_root.parent / ".cache" / "wiki-index.json"


def scan_manifest(wiki_root: Path) -> dict[str, list[int]]:
    """{rel_path: [size, mtime_ns]} for every wiki/**/*.md file — the
    freshness check. Compared byte-for-byte (as JSON) against the cached
    manifest; ANY difference (changed, added, removed file) triggers a full
    rebuild in load_or_build()."""
    manifest: dict[str, list[int]] = {}
    for path in sorted(wiki_root.rglob("*.md")):
        rel = path.relative_to(wiki_root).as_posix()
        st = path.stat()
        manifest[rel] = [st.st_size, st.st_mtime_ns]
    return manifest


def load_or_build(wiki_root: Path, cache_path: Path | None = None) -> dict[str, dict[str, Any]]:
    """The only entry point callers (wiki-query.py, wiki-eval.py, the
    pre-commit check) should use. Rebuilds from scratch whenever the cache is
    missing, corrupt, wrong version, or its manifest doesn't match the
    current filesystem state exactly — see module docstring."""
    wiki_root = wiki_root.resolve()
    cache_path = cache_path or default_cache_path(wiki_root)
    manifest = scan_manifest(wiki_root)

    if cache_path.is_file():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            cached = None
        if (
            isinstance(cached, dict)
            and cached.get("version") == CACHE_VERSION
            and cached.get("manifest") == manifest
        ):
            return cached["index"]

    index = build_index(wiki_root)
    payload = {"version": CACHE_VERSION, "manifest": manifest, "index": index}
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path = cache_path.with_suffix(".tmp")
    tmp_path.write_text(json.dumps(payload, ensure_ascii=False, sort_keys=True), encoding="utf-8")
    tmp_path.replace(cache_path)
    return index


def main() -> int:
    import argparse
    import sys
    import time

    parser = argparse.ArgumentParser(description="Build/refresh the bakery-wiki navigational index cache.")
    parser.add_argument("--wiki-root", type=Path, help="Cesta k adresáři wiki/; výchozí je ../wiki od tohoto skriptu.")
    parser.add_argument("--force", action="store_true", help="Ignoruj existující cache a přegeneruj vždy.")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[1]
    wiki_root = (args.wiki_root or repo_root / "wiki").resolve()
    if not wiki_root.is_dir():
        print(f"{wiki_root}: adresář wiki neexistuje", file=sys.stderr)
        return 1

    cache_path = default_cache_path(wiki_root)
    if args.force and cache_path.is_file():
        cache_path.unlink()

    start = time.perf_counter()
    index = load_or_build(wiki_root, cache_path)
    elapsed = time.perf_counter() - start
    print(f"OK: {len(index)} stránek indexováno za {elapsed*1000:.1f} ms (cache: {cache_path})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
