#!/usr/bin/env python3
"""Read-only integrity validation for the bakery-wiki vault."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path, PurePosixPath


REQUIRED_METADATA = ("title", "type", "tags", "created", "updated")
ROOT_EXCEPTIONS = {"index.md", "log.md", "overview.md"}
REACHABILITY_DIRECTORIES = {"entities", "concepts", "domains", "sources", "workpackages"}
# Precedence used to resolve a bare `[[Name]]` link when the same basename
# exists in more than one top-level folder. "" stands for a top-level
# wiki/*.md page (no folder). entities/ wins ties silently because a bare
# name overwhelmingly means "the thing", i.e. its current-state page;
# anywhere else in the list, resolving still succeeds but is reported as
# AMBIGUOUS_LINK so an author can disambiguate with an explicit path.
FOLDER_PRECEDENCE = ("entities", "concepts", "domains", "", "changelog", "incidents")
PAGE_SIZE_LIMIT = 40_000
LOG_ENTRY_LIMIT = 1_200
# CLAUDE.md's "Délka záznamu v logu" rule (≤1200 characters/entry)
# is explicitly NOT retroactive — "Netýká se to zpětně existujících záznamů
# — historie se nepřepisuje, pravidlo platí pro nově psané záznamy od
# 2026-09-21." Entries dated before this constant predate the rule and are
# never checked against it, no matter how long they are.
LOG_ENTRY_LENGTH_RULE_EFFECTIVE_DATE = date(2026, 9, 21)
WARNING_CODES = {"AMBIGUOUS_LINK", "LOG_ENTRY_TOO_LONG"}
WIKILINK = re.compile(r"\[\[([^\]\n]+)\]\]")
HEADING = re.compile(r"^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")
LOG_ENTRY_HEADING = re.compile(r"^## \[(\d{4}-\d{2}-\d{2})\]")


@dataclass(frozen=True)
class Page:
    path: Path
    rel: str
    lines: tuple[str, ...]
    metadata: dict[str, str]
    headings: frozenset[str]


@dataclass(frozen=True)
class Finding:
    path: str
    line: int
    code: str
    detail: str

    def __str__(self) -> str:
        return f"{self.path}:{self.line}: {self.code}: {self.detail}"


def parse_frontmatter(path: Path, root: Path) -> tuple[dict[str, str], list[Finding]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    rel = path.relative_to(root).as_posix()
    if not lines or lines[0] != "---":
        return {}, [Finding(rel, 1, "MISSING_FRONTMATTER", "očekáván úvodní oddělovač ---")]
    try:
        end = lines.index("---", 1)
    except ValueError:
        return {}, [Finding(rel, 1, "MISSING_FRONTMATTER", "chybí uzavírací oddělovač ---")]

    metadata: dict[str, str] = {}
    findings: list[Finding] = []
    active_key: str | None = None
    for index, line in enumerate(lines[1:end], start=2):
        if not line or line.lstrip().startswith("#"):
            continue
        if line[:1].isspace():
            if active_key is None:
                findings.append(Finding(rel, index, "INVALID_FRONTMATTER", "odsazená hodnota nemá předchozí klíč"))
            continue
        if ":" not in line:
            findings.append(Finding(rel, index, "INVALID_FRONTMATTER", "očekáván klíč a hodnota oddělené dvojtečkou"))
            continue
        key, value = (part.strip() for part in line.split(":", 1))
        if not key:
            findings.append(Finding(rel, index, "INVALID_FRONTMATTER", "klíč musí být neprázdný"))
            continue
        metadata[key] = value
        active_key = key

    for key in REQUIRED_METADATA:
        if not metadata.get(key):
            findings.append(Finding(rel, 1, "MISSING_METADATA", f"chybí povinný klíč {key}"))
    if "tags" in metadata and not (metadata["tags"].startswith("[") and metadata["tags"].endswith("]")):
        findings.append(Finding(rel, 1, "INVALID_FRONTMATTER", "tags musí být YAML-like seznam v hranatých závorkách"))

    parsed_dates: dict[str, date] = {}
    for key in ("created", "updated"):
        value = metadata.get(key)
        if value is None:
            continue
        if not DATE.fullmatch(value):
            findings.append(Finding(rel, 1, "INVALID_DATE", f"{key} musí být ISO datum YYYY-MM-DD"))
            continue
        try:
            parsed_dates[key] = date.fromisoformat(value)
        except ValueError:
            findings.append(Finding(rel, 1, "INVALID_DATE", f"{key} není platné ISO datum: {value}"))
    if {"created", "updated"} <= parsed_dates.keys() and parsed_dates["updated"] < parsed_dates["created"]:
        findings.append(Finding(rel, 1, "INVALID_DATE_ORDER", "updated nesmí být starší než created"))
    return metadata, findings


def page_from_path(path: Path, root: Path) -> Page:
    text = path.read_text(encoding="utf-8")
    lines = tuple(text.splitlines())
    metadata, _ = parse_frontmatter(path, root)
    headings = frozenset(match.group(1).strip() for line in lines if (match := HEADING.match(line)) is not None)
    return Page(path, path.relative_to(root).as_posix(), lines, metadata, headings)


def normalized_rel(value: str) -> str:
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


def expand_candidates(source: Page, target: str) -> list[str]:
    candidates: list[str] = []
    if target.startswith(("./", "../")):
        candidates.append(normalized_rel(f"{PurePosixPath(source.rel).parent}/{target}"))
        if target.startswith("../wiki/"):
            candidates.append(normalized_rel(target.removeprefix("../wiki/")))
    else:
        candidates.append(normalized_rel(target.removeprefix("wiki/")))
    expanded: list[str] = []
    for candidate in candidates:
        expanded.append(candidate)
        if candidate.startswith("wiki/"):
            expanded.append(candidate.removeprefix("wiki/"))
    return expanded


def folder_of(page: Page) -> str:
    parts = PurePosixPath(page.rel).parts
    return parts[0] if len(parts) > 1 else ""


def resolve_bare_target(target: str, pages: dict[str, Page]) -> tuple[Page | None, bool]:
    """Resolve a bare (non path-qualified) link by basename/title across the
    whole vault. When the basename is unique the match is returned as-is.
    When it exists in several top-level folders, FOLDER_PRECEDENCE decides
    deterministically (entities/ first). The bool return value flags
    AMBIGUOUS_LINK: true only when precedence actually had to pick among
    several folders AND the winning folder is not entities/.
    """
    matches = [
        page
        for rel, page in pages.items()
        if rel[:-3] == target or Path(rel).stem == target or page.metadata.get("title") == target
    ]
    if not matches:
        return None, False
    if len(matches) == 1:
        return matches[0], False
    by_folder: dict[str, list[Page]] = {}
    for page in matches:
        by_folder.setdefault(folder_of(page), []).append(page)
    for folder in FOLDER_PRECEDENCE:
        candidates = by_folder.get(folder)
        if candidates:
            chosen = sorted(candidates, key=lambda page: page.rel)[0]
            return chosen, folder != "entities"
    # Every match lives in a folder outside FOLDER_PRECEDENCE (e.g. sources/,
    # workpackages/): still resolve deterministically instead of reporting a
    # false BROKEN_LINK, and flag it since precedence had to pick.
    chosen = sorted(matches, key=lambda page: page.rel)[0]
    return chosen, True


def resolve_target(source: Page, target: str, pages: dict[str, Page]) -> tuple[Page | None, bool]:
    target = target.strip()
    if target.endswith(".md"):
        target = target[:-3]
    if not target:
        return source, False
    for candidate in expand_candidates(source, target):
        page = pages.get(f"{candidate}.md")
        if page is not None:
            return page, False
    return resolve_bare_target(target, pages)


def split_link(value: str) -> tuple[str, str | None]:
    target = value.replace("\\|", "|").split("|", 1)[0].strip()
    if target.startswith("#"):
        return "", target[1:].strip()
    if "#" not in target:
        return target, None
    page, heading = target.split("#", 1)
    return page.strip(), heading.strip()


def normalize_anchor(value: str) -> str:
    return re.sub(r"`", "", value).strip().lower()


def heading_matches_anchor(anchor: str, headings: frozenset[str]) -> bool:
    if anchor in headings:
        return True
    anchor_norm = normalize_anchor(anchor)
    for heading in headings:
        if normalize_anchor(heading) == anchor_norm:
            return True
        heading_norm = normalize_anchor(heading)
        if anchor_norm in heading_norm or heading_norm.startswith(anchor_norm):
            return True
    return False


def wikilink_in_inline_code(line: str, start: int, end: int) -> bool:
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


def scannable_lines(lines: tuple[str, ...]) -> list[tuple[int, str]]:
    result: list[tuple[int, str]] = []
    in_fence = False
    for line_number, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("```"):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        result.append((line_number, line))
    return result


def collect_pages(root: Path) -> tuple[dict[str, Page], list[Finding]]:
    pages: dict[str, Page] = {}
    findings: list[Finding] = []
    for path in sorted(root.rglob("*.md")):
        metadata, page_findings = parse_frontmatter(path, root)
        findings.extend(page_findings)
        page = page_from_path(path, root)
        pages[page.rel] = Page(page.path, page.rel, page.lines, metadata, page.headings)
    return pages, findings


def validate_links(pages: dict[str, Page]) -> list[Finding]:
    findings: list[Finding] = []
    for page in pages.values():
        for line_number, line in scannable_lines(page.lines):
            for match in WIKILINK.finditer(line):
                if wikilink_in_inline_code(line, match.start(), match.end()):
                    continue
                target, anchor = split_link(match.group(1))
                destination, ambiguous = resolve_target(page, target, pages)
                if destination is None:
                    findings.append(Finding(page.rel, line_number, "BROKEN_LINK", f"nenalezena stránka {target or '(aktuální stránka)'}"))
                    continue
                if anchor and not heading_matches_anchor(anchor, destination.headings):
                    findings.append(Finding(page.rel, line_number, "MISSING_ANCHOR", f"stránka {destination.rel} nemá nadpis {anchor}"))
                if ambiguous:
                    findings.append(
                        Finding(
                            page.rel,
                            line_number,
                            "AMBIGUOUS_LINK",
                            f"bare odkaz {target!r} má víc kandidátů, přednost dostala {destination.rel} — upřesni cestu (např. [[{destination.rel[:-3]}]])",
                        )
                    )
    return findings


def validate_reachability(pages: dict[str, Page]) -> list[Finding]:
    index = pages.get("index.md")
    if index is None:
        return [Finding("index.md", 1, "MISSING_INDEX", "pro kontrolu dosažitelnosti chybí wiki/index.md")]
    linked: set[str] = set()
    for _, line in scannable_lines(index.lines):
        for match in WIKILINK.finditer(line):
            target, _ = split_link(match.group(1))
            destination, _ = resolve_target(index, target, pages)
            if destination is not None:
                linked.add(destination.rel)
    findings: list[Finding] = []
    for rel in pages:
        if rel in ROOT_EXCEPTIONS or PurePosixPath(rel).parts[0] not in REACHABILITY_DIRECTORIES:
            continue
        if rel not in linked:
            findings.append(Finding(rel, 1, "UNINDEXED_PAGE", "stránka není přímo odkazována z wiki/index.md"))
    return findings


def validate_log_archives(pages: dict[str, Page]) -> list[Finding]:
    """Every wiki/log/*.md month archive must be linked from wiki/log.md.

    log.md is a dispatcher page and deliberately carries no derived data
    (record counts, date ranges) — those go stale the moment an archive is
    edited. What it MUST carry is which archives exist, so this only checks
    link presence, nothing counted or computed.
    """
    hub = pages.get("log.md")
    if hub is None:
        return []
    linked: set[str] = set()
    for _, line in scannable_lines(hub.lines):
        for match in WIKILINK.finditer(line):
            target, _ = split_link(match.group(1))
            destination, _ = resolve_target(hub, target, pages)
            if destination is not None:
                linked.add(destination.rel)
    findings: list[Finding] = []
    for rel in pages:
        if PurePosixPath(rel).parts[:1] != ("log",):
            continue
        if rel not in linked:
            findings.append(Finding(rel, 1, "UNLINKED_LOG_ARCHIVE", "měsíční archiv logu není odkázaný z wiki/log.md"))
    return findings


def validate_log_entry_length(pages: dict[str, Page]) -> list[Finding]:
    """Warn (never fail) when a wiki/log/*.md entry exceeds LOG_ENTRY_LIMIT chars.

    CLAUDE.md "Délka záznamu v logu" sets a target of ≤1200 characters
    per entry ("záznam je rozcestník v čase, ne úložiště") — measured
    2026-09-21 at ~2760 chars/entry average, ~390k tokens/month of vault
    growth from the log alone. This is a WARNING, not fail-closed: parallel
    sessions write log entries continuously, and blocking a commit over
    prose length mid-write would be disproportionate.

    Entries are split on `## [YYYY-MM-DD]` headings; an entry's text runs
    from its heading up to (not including) the next such heading, or EOF.

    Not retroactive, by explicit rule in CLAUDE.md: only entries dated
    on or after LOG_ENTRY_LENGTH_RULE_EFFECTIVE_DATE are checked — history
    is not rewritten, and older entries were written before the rule
    existed.
    """
    findings: list[Finding] = []
    for rel, page in pages.items():
        if PurePosixPath(rel).parts[:1] != ("log",):
            continue
        starts: list[tuple[int, str]] = []
        for index, line in enumerate(page.lines):
            match = LOG_ENTRY_HEADING.match(line)
            if match is not None:
                starts.append((index, match.group(1)))
        for position, (start_index, date_str) in enumerate(starts):
            end_index = starts[position + 1][0] if position + 1 < len(starts) else len(page.lines)
            try:
                entry_date = date.fromisoformat(date_str)
            except ValueError:
                continue  # malformed date: not this check's job to report
            if entry_date < LOG_ENTRY_LENGTH_RULE_EFFECTIVE_DATE:
                continue
            length = len("\n".join(page.lines[start_index:end_index]))
            if length > LOG_ENTRY_LIMIT:
                findings.append(
                    Finding(
                        rel,
                        start_index + 1,
                        "LOG_ENTRY_TOO_LONG",
                        f"záznam má {length} znaků, cíl je ≤{LOG_ENTRY_LIMIT} znaků "
                        "(CLAUDE.md, sekce „Délka záznamu v logu“)",
                    )
                )
    return findings


def _size_exception_reason(raw: str) -> str:
    """Best-effort "is there an actual reason" trim for a size_exception value.

    parse_frontmatter() deliberately does not strip YAML string quoting for
    any key (other keys, e.g. tags, rely on seeing the raw text), so a
    quoted-empty value like `""` or `''` survives as a two-character
    non-empty string and would otherwise read as "has a reason". Handled
    here, locally, rather than in the generic parser, to avoid changing
    behaviour for every other frontmatter key.
    """
    value = raw.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1].strip()
    return value


def validate_page_sizes(pages: dict[str, Page]) -> list[Finding]:
    """Fail closed when a page exceeds PAGE_SIZE_LIMIT characters.

    Tightened from WARNING to fail-closed on 2026-09-23 (phase A follow-up):
    the previous attempt (45e08e2, 2026-09-22) verified 0 findings and flipped
    this, but a same-day concurrent commit (6ebdbe7) had already grown
    entities/ai-radio.md past the threshold, so the tightening was reverted
    the same day (d30a296) rather than pushed in blind. This time
    entities/ai-radio.md was split into entities/ai-radio/Obsah vysílání.md
    (six sections: Co se vysílá, Měření F0, Návrh obsahu PR#34, F1a+F1b, F1c,
    Měření pokrytí A27 — parent 43 136 → 22 875 chars), and a fresh vault-wide
    re-measure right before this flip found 3 more pages that had drifted
    over the threshold since 45e08e2 (concurrent sessions keep writing):
    each got a page-specific `size_exception:` rather than a split, since
    all three were barely over (396–1137 chars, ~1-3%) and splitting them is
    out of scope for this change. Do not weaken this back to a warning just
    because a new page trips it; split the page, or add a properly justified
    `size_exception:` instead (see the PAGE_TOO_LARGE Finding's detail text,
    which spells out both options).

    Exempt: any page that is an append-only chronological record which is
    never read in full — only grepped, or read from the top — because a
    numbered/dated sequence can't be split into topical sub-pages without
    breaking the chronology. wiki/log/*.md month archives are this; so are
    wiki/changelog/*.md pages (e.g. a single dateless table, or a sequence
    of "Vlna N" sections). Splitting either would just fragment a record
    nobody reads end-to-end, see CLAUDE.md "Vrstvy kontextu".

    Also exempt: a single page carrying a non-empty `size_exception:`
    frontmatter key — a deliberate, per-page override for the rare case
    where splitting would do more damage than the size itself (e.g. a
    chronological log with interleaved resolved/open items and "viz
    výše/níže" references, where a resolved/open or topical split would
    sever that navigation). The reason is mandatory, not decorative: an
    exception nobody has to justify is indistinguishable from neglect, and
    six months later there's no way to tell "still deliberate" from
    "nobody looked at this since". A present-but-empty key — in *any*
    surface form: missing value, whitespace-only, or a quoted empty string
    (`""` / `''`, which YAML would treat as empty but the frontmatter
    parser here keeps verbatim, quotes and all — see _size_exception_reason)
    — is therefore its own finding (SIZE_EXCEPTION_WITHOUT_REASON) instead
    of PAGE_TOO_LARGE, not in addition to it: a present-but-empty key is
    always the author's mistake to fix (write a reason, or delete the key),
    never merely "no exception was requested", so it gets its own
    actionable finding rather than quietly folding back into the generic
    size warning.
    """
    findings: list[Finding] = []
    for rel, page in pages.items():
        if PurePosixPath(rel).parts[:1] in (("log",), ("changelog",)):
            continue
        exception_raw = page.metadata.get("size_exception")
        if exception_raw is not None:
            if _size_exception_reason(exception_raw):
                continue  # deliberate, justified exception: exempt from PAGE_TOO_LARGE
            findings.append(
                Finding(
                    rel,
                    1,
                    "SIZE_EXCEPTION_WITHOUT_REASON",
                    "size_exception je přítomný, ale bez důvodu (prázdný, jen bílé znaky, "
                    "nebo prázdné uvozovky) — výjimka bez důvodu je horší než žádná; buď "
                    "dopiš důvod, nebo klíč z frontmatteru smaž",
                )
            )
            continue  # the missing reason is the actionable problem, not the size
        size = len(page.path.read_text(encoding="utf-8"))
        if size > PAGE_SIZE_LIMIT:
            findings.append(
                Finding(
                    rel,
                    1,
                    "PAGE_TOO_LARGE",
                    f"stránka má {size} znaků, práh je {PAGE_SIZE_LIMIT} — buď stránku rozděl "
                    "(viz CLAUDE.md, sekce „Dělení předimenzovaných stránek: přesouvat, ne "
                    "přepisovat“), nebo do frontmatteru dopiš neprázdný `size_exception: <důvod>`",
                )
            )
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Read-only integrity checker for a bakery-wiki vault.")
    parser.add_argument("--wiki-root", type=Path, help="Cesta k adresáři wiki/; výchozí je ../wiki od tohoto skriptu.")
    args = parser.parse_args()
    root = (args.wiki_root or Path(__file__).resolve().parents[1] / "wiki").resolve()
    if not root.is_dir():
        print(f"{root}:1: MISSING_WIKI_ROOT: adresář wiki neexistuje", file=sys.stderr)
        return 1
    pages, findings = collect_pages(root)
    findings.extend(validate_links(pages))
    findings.extend(validate_reachability(pages))
    findings.extend(validate_log_archives(pages))
    findings.extend(validate_log_entry_length(pages))
    findings.extend(validate_page_sizes(pages))
    findings.sort(key=lambda finding: (finding.path, finding.line, finding.code, finding.detail))
    errors = [finding for finding in findings if finding.code not in WARNING_CODES]
    warnings = [finding for finding in findings if finding.code in WARNING_CODES]
    if findings:
        print(*findings, sep="\n", file=sys.stderr)
    if errors:
        suffix = f" ({len(warnings)} warning(s) also listed above)" if warnings else ""
        print(f"Wiki integrity check failed: {len(errors)} finding(s) across {len(pages)} page(s).{suffix}", file=sys.stderr)
        return 1
    if warnings:
        print(f"Wiki integrity check passed with {len(warnings)} warning(s): {len(pages)} page(s) checked.")
        return 0
    print(f"Wiki integrity check passed: {len(pages)} page(s) checked.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
