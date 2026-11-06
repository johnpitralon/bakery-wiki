#!/usr/bin/env bash
# Process-level contract for the executable wiki-query.py CLI.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
QUERY="$ROOT/tools/wiki-query.py"
TMPROOT="$(mktemp -d)"
VAULT="$TMPROOT/wiki"
PASS=0
FAIL=0
trap 'rm -rf "$TMPROOT"' EXIT

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

make_fixture() {
  mkdir -p "$VAULT/entities" "$VAULT/concepts"

  cat > "$VAULT/entities/Lead.md" <<'EOF'
---
title: Lead
type: entity
tags: [fixture]
created: 2026-09-23
updated: 2026-09-23
---

Lead je testovací entita pro kontrakt CLI.

## Dotazovaná sekce

Pouze cílový obsah sekce s jedinečným vyhledávacím tokenem kontraktniulom.

## Záměrně jiná sekce

Tento text se při výpisu cílové sekce nesmí objevit.

Odkaz na [[concepts/Companion]].
EOF

  cat > "$VAULT/concepts/Companion.md" <<'EOF'
---
title: Companion
type: concept
tags: [fixture]
created: 2026-09-23
updated: 2026-09-23
---

Companion je propojený fixture koncept.

## Souvislost

Odkaz zpět na [[entities/Lead]].
EOF
}

assert_contains() {
  local output="$1"
  local expected="$2"
  local label="$3"
  if grep -Fq "$expected" <<< "$output"; then
    pass "$label"
  else
    fail "$label — chybí: $expected; výstup: $output"
  fi
}

assert_not_contains() {
  local output="$1"
  local unexpected="$2"
  local label="$3"
  if grep -Fq "$unexpected" <<< "$output"; then
    fail "$label — neočekávaný obsah: $unexpected; výstup: $output"
  else
    pass "$label"
  fi
}

make_fixture

if [ -x "$QUERY" ]; then
  pass "wiki-query.py je přímo spustitelný"
else
  fail "wiki-query.py nemá executable bit"
fi

if output=$("$QUERY" --help 2>&1); then
  assert_contains "$output" "search" "help uvádí search"
  assert_contains "$output" "section" "help uvádí section"
  assert_contains "$output" "related" "help uvádí related"
else
  fail "help selhal: $output"
fi

if output=$("$QUERY" --wiki-root "$VAULT" search "kontraktniulom" --top 1 2>&1); then
  assert_contains "$output" "entities/Lead.md#Dotazovaná sekce" "search najde jednoznačný fixture hit"
  if grep -Eq 'řádky [0-9]+–[0-9]+' <<< "$output"; then
    pass "search uvádí rozsah řádků"
  else
    fail "search neuvádí rozsah řádků: $output"
  fi
else
  fail "search selhal: $output"
fi

if output=$("$QUERY" --wiki-root "$VAULT" search "neexistujicivyhledavacitoken" 2>&1); then
  assert_contains "$output" "Žádné zásahy." "search bez zásahů je úspěšný a explicitní"
else
  fail "search bez zásahů selhal: $output"
fi

if output=$("$QUERY" --wiki-root "$VAULT" section entities/Lead "Dotazovaná sekce" 2>&1); then
  assert_contains "$output" "Pouze cílový obsah sekce s jedinečným vyhledávacím tokenem kontraktniulom." "section vypíše vyžádaný obsah"
  assert_not_contains "$output" "Tento text se při výpisu" "section nevypíše sousední sekci"
else
  fail "section selhal: $output"
fi

if output=$("$QUERY" --wiki-root "$VAULT" section entities/Neznámá "Dotazovaná sekce" 2>&1); then
  fail "section neznámé stránky měla selhat: $output"
else
  assert_contains "$output" "Stránka nenalezena" "section neznámé stránky poskytne diagnostiku"
fi

if output=$("$QUERY" --wiki-root "$VAULT" section entities/Lead "Neznámý nadpis" 2>&1); then
  fail "section neznámého nadpisu měla selhat: $output"
else
  assert_contains "$output" "Nadpis" "section neznámého nadpisu poskytne diagnostiku"
  assert_contains "$output" "Dotazovaná sekce" "section neznámého nadpisu vypíše kandidáty"
fi

if output=$("$QUERY" --wiki-root "$VAULT" related entities/Lead 2>&1); then
  assert_contains "$output" "odchozí odkazy" "related uvádí odchozí hrany"
  assert_contains "$output" "příchozí odkazy" "related uvádí příchozí hrany"
  assert_contains "$output" "concepts/Companion" "related vypíše propojenou fixture stránku"
else
  fail "related selhal: $output"
fi

if output=$("$QUERY" --wiki-root "$VAULT" related entities/Neznámá 2>&1); then
  fail "related neznámé stránky měla selhat: $output"
else
  assert_contains "$output" "Stránka nenalezena" "related neznámé stránky poskytne diagnostiku"
fi

echo "Results: $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
