#!/usr/bin/env bash
# Aplikuje <wiki-file> bloky z LLM odpovědi do wiki/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INPUT="${1:-$ROOT/triggers/out/LATEST-response.md}"

if [ ! -f "$INPUT" ]; then
  echo "Usage: $0 [response.md]" >&2
  echo "  (default: triggers/out/LATEST-response.md)" >&2
  exit 1
fi

python3 - "$ROOT" "$INPUT" <<'PY'
import re, sys, pathlib

root = pathlib.Path(sys.argv[1])
src = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")

# <wiki-file path="wiki/foo.md"> ... </wiki-file>
pattern = re.compile(
    r'<wiki-file\s+path="([^"]+)">\s*(.*?)\s*</wiki-file>',
    re.DOTALL | re.IGNORECASE,
)
blocks = pattern.findall(src)

if not blocks:
    # fallback: markdown fenced blocks with path comment
    alt = re.compile(r'<!--\s*path:\s*([^\s]+)\s*-->\s*(```(?:markdown)?\s*\n(.*?)\n```)', re.DOTALL)
    blocks = [(m[0], m[1]) for m in alt.findall(src)]

if not blocks:
    print("ERROR: žádné <wiki-file> bloky v odpovědi", file=sys.stderr)
    sys.exit(1)

for rel, body in blocks:
    rel = rel.strip().lstrip("/")
    if rel.startswith("wiki/"):
        pass
    elif rel.startswith("wiki"):
        rel = rel
    else:
        rel = f"wiki/{rel}" if not rel.startswith("raw/") else rel

    if ".." in pathlib.PurePosixPath(rel).parts:
        print(f"SKIP unsafe path: {rel}", file=sys.stderr)
        continue
    if not rel.startswith("wiki/"):
        print(f"SKIP non-wiki path: {rel}", file=sys.stderr)
        continue

    dest = root / rel
    dest.parent.mkdir(parents=True, exist_ok=True)
    text = body.strip() + "\n"

    # Guard: block absolute paths in wiki
    bad = re.search(r'(/Users/|/home/[^/]+/|C:\\Users)', text)
    if bad:
        print(f"SKIP {rel}: absolutní cesta v obsahu", file=sys.stderr)
        continue

    dest.write_text(text, encoding="utf-8")
    print(f"✓ {rel}")

print(f"\nAplikováno {len(blocks)} soubor(ů). Zkontroluj diff a commitni.")
PY
