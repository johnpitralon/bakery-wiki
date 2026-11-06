#!/usr/bin/env bash
# Fixture tests for tools/wiki_index.py + tools/wiki_search.py + tools/wiki-query.py
# (fáze B — navigační vrstva). Focus: the cache must never be trusted blindly —
# every edit, add, or delete of a wiki/**/*.md file must be picked up on the
# very next call, with no manual "regenerate" step required anywhere.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$ROOT/tools/wiki-query.py"
INDEXER="$ROOT/tools/wiki_index.py"
PY=$(command -v python3 || command -v python) || { echo "chybí python3/python" >&2; exit 1; }
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

VAULT="$TMPROOT/vault"

make_fixture() {
  rm -rf "$VAULT"
  mkdir -p "$VAULT/wiki/entities" "$VAULT/wiki/concepts"
  cat > "$VAULT/wiki/index.md" <<'EOF'
---
title: Index
type: overview
tags: [meta]
created: 2026-09-11
updated: 2026-09-11
---

Katalog stránek.

[[entities/Thing]]
[[concepts/Other]]
EOF
  cat > "$VAULT/wiki/entities/Thing.md" <<'EOF'
---
title: Thing
type: entity
tags: [fixture]
created: 2026-09-11
updated: 2026-09-11
---

Thing je fixture entita pro testy indexeru.

## Present heading

Původní text sekce, verze jedna.

## Druhá sekce

Odkaz na [[concepts/Other]].
EOF
  cat > "$VAULT/wiki/concepts/Other.md" <<'EOF'
---
title: Other
type: concept
tags: [fixture]
created: 2026-09-11
updated: 2026-09-11
---

Other je fixture koncept.

## Jiná sekce

Nic moc tady není.
EOF
}

# --- 1. build z čista: očekávané stránky, sekce, odkazy -------------------
make_fixture
if output=$("$PY" "$INDEXER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'OK: 3 stránek' <<< "$output"; then
    pass 'čerstvý build najde přesně 3 stránky'
  else
    fail "čerstvý build — neočekávaný výstup: $output"
  fi
else
  fail "čerstvý build selhal: $output"
fi
CACHE="$VAULT/.cache/wiki-index.json"
if [ -f "$CACHE" ]; then
  pass 'cache soubor vznikl mimo wiki/ (pod .cache/)'
else
  fail 'cache soubor nevznikl na očekávaném místě'
fi

# --- 2. section vytáhne přesný text, ne celou stránku ----------------------
if output=$("$PY" "$QUERY" --wiki-root "$VAULT/wiki" section entities/Thing "Present heading" 2>&1); then
  if grep -Fq 'verze jedna' <<< "$output" && ! grep -Fq 'Jiná sekce' <<< "$output"; then
    pass 'section vrátí jen požadovanou sekci, ne cizí obsah'
  else
    fail "section — neočekávaný obsah: $output"
  fi
else
  fail "section selhal: $output"
fi

# --- 3. STALENESS: editace obsahu MUSÍ se projevit hned při dalším volání --
sleep 0.05  # zajistí odlišný mtime_ns i na hrubších FS hodinách
sed -i.bak 's/Původní text sekce, verze jedna\./Přepsaný text sekce, verze dva./' "$VAULT/wiki/entities/Thing.md"
rm -f "$VAULT/wiki/entities/Thing.md.bak"
if output=$("$PY" "$QUERY" --wiki-root "$VAULT/wiki" section entities/Thing "Present heading" 2>&1); then
  if grep -Fq 'verze dva' <<< "$output" && ! grep -Fq 'verze jedna' <<< "$output"; then
    pass 'editace obsahu je vidět HNED při dalším dotazu (žádná zastaralá cache)'
  else
    fail "staleness — pořád vidím starý obsah: $output"
  fi
else
  fail "section po editaci selhal: $output"
fi

# --- 4. STALENESS: nová stránka se objeví bez ručního kroku ----------------
cat > "$VAULT/wiki/entities/NewThing.md" <<'EOF'
---
title: NewThing
type: entity
tags: [fixture]
created: 2026-09-11
updated: 2026-09-11
---

Nová fixture stránka přidaná po prvním buildu.

## Nová sekce

Unikátní slovo gizmoflexnewthing.
EOF
if output=$("$PY" "$QUERY" --wiki-root "$VAULT/wiki" search "gizmoflexnewthing" --top 5 2>&1); then
  if grep -Fq 'entities/NewThing' <<< "$output"; then
    pass 'nově přidaná stránka je dohledatelná bez ručního přegenerování'
  else
    fail "nová stránka nenalezena po přidání: $output"
  fi
else
  fail "search po přidání stránky selhal: $output"
fi

# --- 5. STALENESS: smazaná stránka zmizí z indexu --------------------------
rm "$VAULT/wiki/entities/NewThing.md"
if output=$("$PY" "$QUERY" --wiki-root "$VAULT/wiki" related entities/Thing 2>&1); then
  if ! grep -Fq 'NewThing' <<< "$output"; then
    pass 'smazaná stránka zmizí z indexu bez ručního přegenerování'
  else
    fail "smazaná stránka pořád v indexu: $output"
  fi
else
  fail "related po smazání stránky selhal: $output"
fi

# --- 6. beze změny obsahu je cache bajtově stabilní (deterministický výstup)
make_fixture
"$PY" "$INDEXER" --wiki-root "$VAULT/wiki" --force > /dev/null
hash1=$(shasum -a 256 "$VAULT/.cache/wiki-index.json" 2>/dev/null | cut -d' ' -f1 || sha256sum "$VAULT/.cache/wiki-index.json" | cut -d' ' -f1)
rm -rf "$VAULT/.cache"
"$PY" "$INDEXER" --wiki-root "$VAULT/wiki" --force > /dev/null
hash2=$(shasum -a 256 "$VAULT/.cache/wiki-index.json" 2>/dev/null | cut -d' ' -f1 || sha256sum "$VAULT/.cache/wiki-index.json" | cut -d' ' -f1)
if [ "$hash1" = "$hash2" ]; then
  pass 'stejný vstup -> bajtově identická cache (deterministický výstup)'
else
  fail 'stejný vstup dal jinou cache -> generátor není deterministický'
fi

# --- 7. section na nejednoznačný/neexistující nadpis je diagnostický, ne pád
make_fixture
if output=$("$PY" "$QUERY" --wiki-root "$VAULT/wiki" section entities/Thing "Tenhle nadpis neexistuje" 2>&1); then
  fail 'neexistující nadpis — očekáván nenulový exit'
elif grep -Fq 'Present heading' <<< "$output" || grep -Fq 'Druhá sekce' <<< "$output"; then
  pass 'neexistující nadpis vypíše dostupné nadpisy jako nápovědu'
else
  fail "neexistující nadpis — chybí užitečná diagnostika: $output"
fi

# --- 8. skutečný vault repa: index vůbec doběhne a najde stovky stránek ----
if output=$("$PY" "$INDEXER" --wiki-root "$ROOT/wiki" --force 2>&1); then
  count=$(grep -oE 'OK: [0-9]+' <<< "$output" | grep -oE '[0-9]+')
  if [ "${count:-0}" -gt 10 ]; then
    pass "skutečný vault repa: index doběhne (${count} stránek)"
  else
    fail "skutečný vault repa — podezřele málo stránek: $output"
  fi
else
  fail "skutečný vault repa — build selhal: $output"
fi
rm -rf "$ROOT/.cache"

echo "Results: $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
