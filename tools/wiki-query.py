#!/usr/bin/env python3
"""wiki-query.py — navigational layer over the bakery-wiki vault (fáze B).

Three commands, all read-only, no network, no external dependencies:

  search "<dotaz>" [--type T] [--top N] [--graph]
      BM25-like ranked hits, one per page, each citing its best-matching
      section as "cesta#nadpis (řádky A–B)" + the page's one-sentence
      summary. --graph turns on one-hop link-graph expansion (see
      tools/wiki_search.py docstring) — off by default so its effect can be
      measured (tools/wiki-eval.py: wiki_query vs wiki_query_graph).

  section <cesta> <nadpis>
      Prints exactly one section's text, verbatim, by line range from the
      index — the actual point of this phase: the cost of an answer stops
      scaling with the whole page's size.

  related <cesta>
      Direct link-graph neighbors (outbound + inbound `[[links]]`).

The index itself (tools/wiki_index.py) is a local, gitignored, always-fresh
cache — never trust anything here without going through load_or_build().
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import wiki_index  # noqa: E402
import wiki_search  # noqa: E402


def _wiki_root(args: argparse.Namespace) -> Path:
    repo_root = Path(__file__).resolve().parents[1]
    return (args.wiki_root or repo_root / "wiki").resolve()


def cmd_search(args: argparse.Namespace) -> int:
    wiki_root = _wiki_root(args)
    index = wiki_index.load_or_build(wiki_root)
    hits = wiki_search.search(
        index,
        wiki_root,
        args.query,
        top_k=args.top,
        type_filter=args.type,
        graph_expand=args.graph,
    )
    if not hits:
        print("Žádné zásahy.")
        return 0
    for i, hit in enumerate(hits, start=1):
        heading = hit.heading or "(úvod)"
        print(f"{i}. {hit.path}#{heading} (řádky {hit.start_line}–{hit.end_line})  score={hit.score:.2f}")
        if hit.summary:
            print(f"   {hit.summary}")
    return 0


def cmd_section(args: argparse.Namespace) -> int:
    wiki_root = _wiki_root(args)
    index = wiki_index.load_or_build(wiki_root)
    page_id = wiki_search.resolve_page_id(index, args.path)
    if page_id is None:
        print(f"Stránka nenalezena: {args.path!r}", file=sys.stderr)
        return 1
    section, candidates = wiki_search.find_section(index, page_id, args.heading)
    if section is None:
        print(f"Nadpis {args.heading!r} na stránce {page_id} nejednoznačný nebo nenalezený.", file=sys.stderr)
        if candidates:
            print("Dostupné nadpisy:", file=sys.stderr)
            for c in candidates:
                print(f"  - {c}", file=sys.stderr)
        return 1
    page = index[page_id]
    full_path = wiki_root / page["path"]
    lines = full_path.read_text(encoding="utf-8").splitlines()
    start, end = section["start_line"], section["end_line"]
    print(f"{page_id}#{section['heading']} (řádky {start}–{end})")
    print()
    print("\n".join(lines[start - 1 : end]))
    return 0


def cmd_related(args: argparse.Namespace) -> int:
    wiki_root = _wiki_root(args)
    index = wiki_index.load_or_build(wiki_root)
    page_id = wiki_search.resolve_page_id(index, args.path)
    if page_id is None:
        print(f"Stránka nenalezena: {args.path!r}", file=sys.stderr)
        return 1
    neighbors = wiki_search.related(index, page_id)
    print(f"{page_id}")
    print(f"  odchozí odkazy ({len(neighbors['links_out'])}):")
    for n in neighbors["links_out"]:
        print(f"    - {n['page_id']} [{n['type']}] {n['title']}")
    print(f"  příchozí odkazy ({len(neighbors['links_in'])}):")
    for n in neighbors["links_in"]:
        print(f"    - {n['page_id']} [{n['type']}] {n['title']}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--wiki-root", type=Path, help="Cesta k adresáři wiki/; výchozí je ../wiki od tohoto skriptu.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_search = sub.add_parser("search", help="BM25-like sekční hledání")
    p_search.add_argument("query")
    p_search.add_argument("--type", default=None, help="Filtruj podle frontmatter type (entity|concept|domain|...)")
    p_search.add_argument("--top", type=int, default=5)
    p_search.add_argument("--graph", action="store_true", help="Zapni jednoskokové rozšíření po grafu odkazů (B2b)")
    p_search.set_defaults(func=cmd_search)

    p_section = sub.add_parser("section", help="Vytáhni přesně jednu sekci stránky")
    p_section.add_argument("path")
    p_section.add_argument("heading")
    p_section.set_defaults(func=cmd_section)

    p_related = sub.add_parser("related", help="Sousedi v grafu odkazů")
    p_related.add_argument("path")
    p_related.set_defaults(func=cmd_related)

    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
