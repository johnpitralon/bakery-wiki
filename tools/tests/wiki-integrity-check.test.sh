#!/usr/bin/env bash
# Fixture and pre-commit tests for tools/wiki-integrity-check.py.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/tools/wiki-integrity-check.py"
# Windows (Git Bash) často nemá `python3`, jen `python` — stejný fallback jako v pre-commit hooku.
PY=$(command -v python3 || command -v python) || { echo "chybí python3/python" >&2; exit 1; }
HOOK="$ROOT/.githooks/pre-commit"
TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
PASS=0
FAIL=0

pass() { echo "PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $1"; FAIL=$((FAIL + 1)); }

# Přenositelná in-place editace: GNU sed bere `-i` bez přípony, BSD sed (macOS)
# vyžaduje `-i ''` — proto sed → temp → mv, funguje na macOS, Linuxu i v Git Bash.
sed_inplace() {
  local expr="$1" file="$2"
  sed "$expr" "$file" > "$file.tmp" && mv "$file.tmp" "$file"
}

make_fixture() {
  VAULT="$TMPROOT/vault"
  rm -rf "$VAULT"
  mkdir -p "$VAULT/wiki/entities"
  cat > "$VAULT/wiki/index.md" <<'EOF'
---
title: Index
type: overview
tags: [meta]
created: 2026-09-11
updated: 2026-09-11
---

[[entities/Thing]]
EOF
  cat > "$VAULT/wiki/entities/Thing.md" <<'EOF'
---
title: Thing
type: entity
tags: [fixture]
created: 2026-09-11
updated: 2026-09-11
---

## Present anchor
EOF
}

expect_success() {
  local label="$1" output
  if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
    grep -Fq 'Wiki integrity check passed:' <<< "$output" && pass "$label" || fail "$label — chybí souhrn: $output"
  else
    fail "$label — očekáván exit 0: $output"
  fi
}

expect_failure() {
  local label="$1" path="$2" code="$3" output
  if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
    fail "$label — očekáván exit 1"
  elif grep -Fq "$path" <<< "$output" && grep -Fq "$code" <<< "$output"; then
    pass "$label"
  else
    fail "$label — chybí $path nebo $code: $output"
  fi
}

make_fixture
expect_success 'čistý fixture projde se souhrnem'
make_fixture
sed_inplace 's/updated: 2026-09-11/updated: 2026-02-30/' "$VAULT/wiki/entities/Thing.md"
expect_failure 'neplatné datum je fail-closed' 'entities/Thing.md' 'INVALID_DATE'
make_fixture
sed_inplace 's/updated: 2026-09-11/updated: 2026-01-01/' "$VAULT/wiki/entities/Thing.md"
expect_failure 'obrácené pořadí dat je fail-closed' 'entities/Thing.md' 'INVALID_DATE_ORDER'
make_fixture
sed_inplace '/type: entity/d' "$VAULT/wiki/entities/Thing.md"
expect_failure 'chybějící metadata jsou fail-closed' 'entities/Thing.md' 'MISSING_METADATA'
make_fixture
printf '\n[[entities/Missing]]\n' >> "$VAULT/wiki/entities/Thing.md"
expect_failure 'chybějící target je fail-closed' 'entities/Thing.md' 'BROKEN_LINK'
make_fixture
sed_inplace 's|\[\[entities/Thing\]\]|[[entities/Thing#Absent anchor]]|' "$VAULT/wiki/index.md"
expect_failure 'chybějící anchor je fail-closed' 'index.md' 'MISSING_ANCHOR'
make_fixture
mkdir -p "$VAULT/wiki/concepts"
cp "$VAULT/wiki/entities/Thing.md" "$VAULT/wiki/concepts/Orphan.md"
expect_failure 'neindexovaná stránka je fail-closed' 'concepts/Orphan.md' 'UNINDEXED_PAGE'

make_fixture
mkdir -p "$VAULT/wiki/log"
cat > "$VAULT/wiki/log.md" <<'EOF'
---
title: Log
type: overview
tags: [log, meta]
created: 2026-09-11
updated: 2026-09-11
---

## Archivy podle měsíce

- [[log/2026-09]]
EOF
cat > "$VAULT/wiki/log/2026-09.md" <<'EOF'
---
title: Log 2026-09
type: overview
tags: [log, meta, archiv]
created: 2026-09-11
updated: 2026-09-11
---

Archiv záznamů za září 2026.
EOF
expect_success 'odkázaný měsíční archiv logu projde'
make_fixture
mkdir -p "$VAULT/wiki/log"
cat > "$VAULT/wiki/log.md" <<'EOF'
---
title: Log
type: overview
tags: [log, meta]
created: 2026-09-11
updated: 2026-09-11
---

## Archivy podle měsíce

- [[log/2026-08]]
EOF
cat > "$VAULT/wiki/log/2026-09.md" <<'EOF'
---
title: Log 2026-09
type: overview
tags: [log, meta, archiv]
created: 2026-09-11
updated: 2026-09-11
---

Archiv záznamů za září 2026.
EOF
cat > "$VAULT/wiki/log/2026-08.md" <<'EOF'
---
title: Log 2026-08
type: overview
tags: [log, meta, archiv]
created: 2026-09-11
updated: 2026-09-11
---

Archiv záznamů za srpen 2026.
EOF
expect_failure 'neodkázaný měsíční archiv logu je fail-closed' 'log/2026-09.md' 'UNLINKED_LOG_ARCHIVE'

# --- page size cap (2026-09-21, zpřísněno na fail-closed 2026-09-23) --------
# PAGE_TOO_LARGE je od druhého pokusu o zpřísnění fail-closed: nad 40 000
# znaků commit neprojde (exit 1), pokud stránka nemá `size_exception`. První
# pokus (45e08e2, 2026-09-22) byl ještě týž den vrácen (d30a296), protože
# souběžná session vytáhla entities/ai-radio.md nad práh dřív, než zpřísnění
# stihlo dojít — tentokrát byla ai-radio rozdělena na pod-stránku (viz
# entities/ai-radio/Obsah vysílání) a čerstvé re-měření celého vaultu před
# zpřísněním potvrdilo nulu neošetřených nálezů. wiki/log/*.md a
# wiki/changelog/*.md jsou z kontroly vyňaté, protože jde o append-only
# chronologické záznamy, které se nikdy nečtou celé.
make_fixture
"$PY" -c "print('x' * 40001)" >> "$VAULT/wiki/entities/Thing.md"
expect_failure 'stránka nad stropem velikosti je fail-closed' 'entities/Thing.md' 'PAGE_TOO_LARGE'

make_fixture
mkdir -p "$VAULT/wiki/log"
cat > "$VAULT/wiki/log.md" <<'EOF'
---
title: Log
type: overview
tags: [log, meta]
created: 2026-09-11
updated: 2026-09-11
---

## Archivy podle měsíce

- [[log/2026-09]]
EOF
{
  cat <<'EOF'
---
title: Log 2026-09
type: overview
tags: [log, meta, archiv]
created: 2026-09-11
updated: 2026-09-11
---

Archiv záznamů za září 2026.
EOF
  "$PY" -c "print('x' * 40001)"
} > "$VAULT/wiki/log/2026-09.md"
if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'PAGE_TOO_LARGE' <<< "$output"; then
    fail "archiv logu nad stropem velikosti — PAGE_TOO_LARGE nemělo padnout: $output"
  else
    pass 'archiv logu nad stropem velikosti je vyňatý (žádné varování)'
  fi
else
  fail "archiv logu nad stropem velikosti — očekáván exit 0: $output"
fi

make_fixture
mkdir -p "$VAULT/wiki/changelog"
{
  cat <<'EOF'
---
title: Changelog Thing
type: overview
tags: [changelog, meta]
created: 2026-09-11
updated: 2026-09-11
---

| Datum | Změna |
| --- | --- |
EOF
  "$PY" -c "print('x' * 40001)"
} > "$VAULT/wiki/changelog/Thing.md"
if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'PAGE_TOO_LARGE' <<< "$output"; then
    fail "changelog nad stropem velikosti — PAGE_TOO_LARGE nemělo padnout: $output"
  else
    pass 'changelog nad stropem velikosti je vyňatý (žádné varování)'
  fi
else
  fail "changelog nad stropem velikosti — očekáván exit 0: $output"
fi

# --- size_exception: vědomá výjimka ze stropu s povinným důvodem (2026-09-21) --
make_fixture
"$PY" -c "print('x' * 40001)" >> "$VAULT/wiki/entities/Thing.md"
sed_inplace 's/tags: \[fixture\]/tags: [fixture]\nsize_exception: Chronologicky provazany dennik, deleni by pretrhalo navaznost./' "$VAULT/wiki/entities/Thing.md"
if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'PAGE_TOO_LARGE' <<< "$output"; then
    fail "size_exception s důvodem — PAGE_TOO_LARGE nemělo padnout: $output"
  else
    pass 'size_exception s neprázdným důvodem potlačí PAGE_TOO_LARGE'
  fi
else
  fail "size_exception s důvodem — očekáván exit 0: $output"
fi

# Pět tvarů "prázdno": chybějící hodnota, jen mezery, a tři varianty prázdných
# uvozovek (dvojité, jednoduché, s mezerami uvnitř) — generický frontmatter
# parser uvozovky nestrhává, takže `size_exception: ""` bez zvláštního
# ošetření projde jako dvouznakový neprázdný řetězec ("díra" nalezená
# 2026-09-21). Každý tvar musí dát SIZE_EXCEPTION_WITHOUT_REASON a NESMÍ
# spadnout zpět na PAGE_TOO_LARGE (to by zamlžilo, že chyba je v chybějícím
# důvodu, ne v absenci výjimky).
for shape_line in \
  'size_exception:' \
  'size_exception:   ' \
  'size_exception: ""' \
  "size_exception: ''" \
  'size_exception: "   "'
do
  make_fixture
  "$PY" -c "print('x' * 40001)" >> "$VAULT/wiki/entities/Thing.md"
  sed_inplace "s/tags: \[fixture\]/tags: [fixture]\n${shape_line}/" "$VAULT/wiki/entities/Thing.md"
  if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
    fail "size_exception tvar '$shape_line' — očekáván exit 1 (SIZE_EXCEPTION_WITHOUT_REASON): $output"
  elif ! grep -Fq 'SIZE_EXCEPTION_WITHOUT_REASON' <<< "$output"; then
    fail "size_exception tvar '$shape_line' — chybí SIZE_EXCEPTION_WITHOUT_REASON: $output"
  elif grep -Fq 'PAGE_TOO_LARGE' <<< "$output"; then
    fail "size_exception tvar '$shape_line' — nesmí tiše spadnout zpět na PAGE_TOO_LARGE: $output"
  else
    pass "size_exception tvar '$shape_line' je nález SIZE_EXCEPTION_WITHOUT_REASON, ne PAGE_TOO_LARGE"
  fi
done

# --- délka záznamu v logu (úkol A4/2, 2026-09-22) ---------------------------
# CONVENTIONS.md "Délka záznamu v logu": cíl ≤1200 znaků/záznam. Kontrola je
# jen warning (paralelní session píšou průběžně, blokovat commit kvůli délce
# prózy by bylo nepřiměřené) a NENÍ zpětná — platí jen pro záznamy datované
# LOG_ENTRY_LENGTH_RULE_EFFECTIVE_DATE (2026-09-21) a novější.
make_fixture
mkdir -p "$VAULT/wiki/log"
cat > "$VAULT/wiki/log/2026-09.md" <<'EOF'
---
title: Log 2026-09
type: overview
tags: [log, meta, archiv]
created: 2026-09-01
updated: 2026-09-22
---

Archiv záznamů za září 2026.

## [2026-09-21] test | Krátký záznam pod limitem

Krátké tělo záznamu, výrazně pod limitem 1200 znaků.
EOF
if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'LOG_ENTRY_TOO_LONG' <<< "$output"; then
    fail "log záznam pod limitem po datu účinnosti — nemělo padnout LOG_ENTRY_TOO_LONG: $output"
  else
    pass 'log záznam pod limitem po datu účinnosti je tichý'
  fi
else
  fail "log záznam pod limitem po datu účinnosti — očekáván exit 0: $output"
fi

make_fixture
mkdir -p "$VAULT/wiki/log"
{
  cat <<'EOF'
---
title: Log 2026-09
type: overview
tags: [log, meta, archiv]
created: 2026-09-01
updated: 2026-09-22
---

Archiv záznamů za září 2026.

## [2026-09-21] test | Dlouhý záznam nad limitem

EOF
  "$PY" -c "print('x' * 1300)"
} > "$VAULT/wiki/log/2026-09.md"
if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'LOG_ENTRY_TOO_LONG' <<< "$output" && grep -Fq 'log/2026-09.md' <<< "$output"; then
    pass 'log záznam nad limitem po datu účinnosti je varování (exit 0)'
  else
    fail "log záznam nad limitem po datu účinnosti — chybí LOG_ENTRY_TOO_LONG: $output"
  fi
else
  fail "log záznam nad limitem po datu účinnosti — očekáván exit 0: $output"
fi

make_fixture
mkdir -p "$VAULT/wiki/log"
{
  cat <<'EOF'
---
title: Log 2026-09
type: overview
tags: [log, meta, archiv]
created: 2026-09-01
updated: 2026-09-22
---

Archiv záznamů za září 2026.

## [2026-09-20] test | Dlouhý záznam PŘED datem účinnosti

EOF
  "$PY" -c "print('x' * 1300)"
} > "$VAULT/wiki/log/2026-09.md"
if output=$("$PY" "$CHECKER" --wiki-root "$VAULT/wiki" 2>&1); then
  if grep -Fq 'LOG_ENTRY_TOO_LONG' <<< "$output"; then
    fail "log záznam nad limitem PŘED datem účinnosti — pravidlo není zpětné, nemělo padnout: $output"
  else
    pass 'log záznam nad limitem před datem účinnosti je tichý (pravidlo není zpětné)'
  fi
else
  fail "log záznam nad limitem před datem účinnosti — očekáván exit 0: $output"
fi

HOOK_REPO="$TMPROOT/hook-repo"
mkdir -p "$HOOK_REPO/tools" "$HOOK_REPO/.githooks"
cp "$CHECKER" "$HOOK_REPO/tools/wiki-integrity-check.py"
# fáze B: pre-commit also runs tools/wiki_index.py (verify-only, see
# .githooks/pre-commit) — needs to exist in this fixture repo too, or every
# commit here would fail on a missing file that has nothing to do with what
# each test below actually exercises.
cp "$ROOT/tools/wiki_index.py" "$HOOK_REPO/tools/wiki_index.py"
cp "$HOOK" "$HOOK_REPO/.githooks/pre-commit"
make_fixture
cp -R "$VAULT/wiki" "$HOOK_REPO/wiki"
git -C "$HOOK_REPO" init -q
git -C "$HOOK_REPO" config user.email test@example.com
git -C "$HOOK_REPO" config user.name 'Wiki integrity test'
git -C "$HOOK_REPO" add wiki
git -C "$HOOK_REPO" -c core.hooksPath=/dev/null commit -qm 'fixture baseline'
sed_inplace 's/updated: 2026-09-11/updated: 2026-02-30/' "$HOOK_REPO/wiki/entities/Thing.md"
git -C "$HOOK_REPO" add wiki/entities/Thing.md
if output=$(git -C "$HOOK_REPO" -c core.hooksPath=.githooks commit -m 'broken wiki' 2>&1); then
  fail 'pre-commit blokuje rozbitou wiki — očekáván exit 1'
elif grep -Fq 'INVALID_DATE' <<< "$output"; then
  pass 'pre-commit blokuje rozbitou wiki s diagnostikou'
else
  fail "pre-commit blokuje rozbitou wiki — chybí diagnostika: $output"
fi
git -C "$HOOK_REPO" reset -- wiki/entities/Thing.md
git -C "$HOOK_REPO" checkout -q -- wiki/entities/Thing.md

# Fail-open regrese (2026-09-14): když je stagnutá jen NEentitní wiki stránka,
# entitní lint blok se přeskočí a jeho `if` vrátí 0. Bez `|| exit 1` u volání
# checkeru se tím nenulový výsledek integrity kontroly zahodí a commit projde
# i s rozbitou wiki — tenhle test drží fail-closed chování i pro tuhle větev.
sed_inplace 's/updated: 2026-09-11/updated: 2026-02-30/' "$HOOK_REPO/wiki/index.md"
git -C "$HOOK_REPO" add wiki/index.md
if output=$(git -C "$HOOK_REPO" -c core.hooksPath=.githooks commit -m 'broken non-entity wiki' 2>&1); then
  fail 'pre-commit blokuje rozbitou wiki i bez entitní stránky — commit prošel (fail-open)'
elif grep -Fq 'INVALID_DATE' <<< "$output"; then
  pass 'pre-commit blokuje rozbitou wiki i bez entitní stránky (fail-closed)'
else
  fail "pre-commit blokuje rozbitou wiki i bez entitní stránky — chybí diagnostika: $output"
fi
git -C "$HOOK_REPO" reset -q -- wiki/index.md
git -C "$HOOK_REPO" checkout -q -- wiki/index.md

# --- bakery-sync install check (non-blocking nudge) ---------------------------
# The fixture needs tools/bakery-sync/install.sh for the check to apply at all.
mkdir -p "$HOOK_REPO/tools/bakery-sync"
: > "$HOOK_REPO/tools/bakery-sync/install.sh"
WSH="$TMPROOT/wsh"
sync_commit() {
  # sync_commit <msg> — commit a trivial change, output in $output, rc in $rc
  printf '%s\n' "$1" >> "$HOOK_REPO/sync-probe.txt"
  git -C "$HOOK_REPO" add sync-probe.txt
  rc=0
  output=$(BAKERY_SYNC_HOME="$WSH" git -C "$HOOK_REPO" -c core.hooksPath=.githooks commit -m "$1" 2>&1) || rc=$?
}
rm -rf "$WSH"
sync_commit 'sync: no install'
if [ "$rc" -eq 0 ] && grep -Fq 'bakery-sync hooky nejsou nainstalované' <<< "$output"; then
  pass 'pre-commit: chybějící ~/.bakery-sync vypíše poznámku a commit projde'
else
  fail "pre-commit: chybějící bakery-sync — rc=$rc: $output"
fi
mkdir -p "$WSH/hooks"
echo '# old lib without the updater' > "$WSH/hooks/lib.sh"
sync_commit 'sync: stale lib'
if [ "$rc" -eq 0 ] && grep -Fq 'zastaralé' <<< "$output" && grep -Fq 'tools/bakery-sync/install.sh' <<< "$output"; then
  pass 'pre-commit: zastaralý lib.sh vypíše varování s příkazem a commit projde'
else
  fail "pre-commit: zastaralý lib.sh — rc=$rc: $output"
fi
echo 'self_update_hooks() { :; }' > "$WSH/hooks/lib.sh"
sync_commit 'sync: current lib'
if [ "$rc" -eq 0 ] && ! grep -Fq 'bakery-sync:' <<< "$output"; then
  pass 'pre-commit: aktuální lib.sh nevypíše nic'
else
  fail "pre-commit: aktuální lib.sh — rc=$rc: $output"
fi
rm -rf "$HOOK_REPO/tools/bakery-sync"
git -C "$HOOK_REPO" rm -qf sync-probe.txt
git -C "$HOOK_REPO" -c core.hooksPath=/dev/null commit -qm 'drop sync probe'

printf 'non-wiki change\n' > "$HOOK_REPO/notes.txt"
git -C "$HOOK_REPO" add notes.txt
if output=$(git -C "$HOOK_REPO" -c core.hooksPath=.githooks commit -m 'non wiki change' 2>&1); then
  if grep -Fq 'Kontrola integrity wiki' <<< "$output"; then
    fail 'pre-commit přeskočí checker bez staged wiki souboru'
  else
    pass 'pre-commit přeskočí checker bez staged wiki souboru'
  fi
else
  fail "pre-commit bez staged wiki souboru selhal: $output"
fi

# --- interpreter probe (2026-09-14) -----------------------------------------
# Na Windows je `python3` na PATH i na stroji bez Pythonu ("app execution
# alias" stub: vypíše hlášku o Microsoft Storu a skončí s exit 49). Sonda
# proto nesmí věřit `command -v` — musí kandidáta zkusit SPUSTIT.
STUBS="$TMPROOT/stubs-all"
mkdir -p "$STUBS"
for name in python3 python py; do
  cat > "$STUBS/$name" <<'STUB'
#!/usr/bin/env bash
echo "Python was not found; run without arguments to install from the Microsoft Store, or disable this shortcut from Settings > Apps > Advanced app settings > App execution aliases."
exit 49
STUB
  chmod 0755 "$STUBS/$name"
done

# Jen `python3` je stub; `python` je funkční (přeposílá na reálný interpret),
# takže sonda musí stub přeskočit a commit projít.
STUB_ONE="$TMPROOT/stubs-python3-only"
mkdir -p "$STUB_ONE"
cp "$STUBS/python3" "$STUB_ONE/python3"
cat > "$STUB_ONE/python" <<STUB
#!/usr/bin/env bash
exec "$PY" "\$@"
STUB
chmod 0755 "$STUB_ONE/python"

git -C "$HOOK_REPO" reset -q -- . || true
git -C "$HOOK_REPO" checkout -q -- wiki 2>/dev/null || true
sed_inplace 's/updated: 2026-09-11/updated: 2026-09-12/' "$HOOK_REPO/wiki/entities/Thing.md"
git -C "$HOOK_REPO" add wiki/entities/Thing.md

if output=$(PATH="$STUBS:$PATH" git -C "$HOOK_REPO" -c core.hooksPath=.githooks commit -m 'stub only' 2>&1); then
  fail 'sonda interpretu: samé stuby musí commit zablokovat (fail-closed)'
elif grep -Fq "chybí funkční Python 3" <<< "$output"; then
  pass 'sonda interpretu: samé stuby → commit blokován vlastní diagnostikou'
else
  fail "sonda interpretu: chybí vlastní diagnostika, dostal jsem: $output"
fi

if output=$(PATH="$STUB_ONE:$PATH" git -C "$HOOK_REPO" -c core.hooksPath=.githooks commit -m 'python3 stub, python works' 2>&1); then
  pass 'sonda interpretu: stub python3 přeskočen, použit funkční python'
else
  fail "sonda interpretu: funkční python nebyl použit: $output"
fi

echo "Results: $PASS passed, $FAIL failed"
test "$FAIL" -eq 0
