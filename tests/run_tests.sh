#!/usr/bin/env bash
# =============================================================================
# zmr test suite
# Usage: ./run_tests.sh [path/to/zmr.py] [category]
#
# category: all | zoom | backtrack | transform | template | fileio | inplace | combined
#           (default: all)
# =============================================================================

set -o pipefail || true
ACTUAL_RC=0
TMPOUT=$(mktemp)

ZMR="${1:-../zmr}"
CATEGORY="${2:-all}"
DIR="$(cd "$(dirname "$0")" && pwd)"
FIXTURES="$DIR/fixtures"

if [[ ! -f "$ZMR" ]]; then
    echo "ERROR: zmr not found at: $ZMR"
    echo "Usage: $0 path/to/zmr.py [category]"
    exit 2
fi

ZMR="python3 $ZMR"

# ── counters ──────────────────────────────────────────────────────────────────
PASS=0
FAIL=0
SKIP=0

pass() {
    echo "  PASS  $1"
    ((PASS++))
}
pass_() {
    echo "  PASS  $1"
    echo "        expected: $(echo "$2"|head -3|cat -v)"
    echo "        got:      $(echo "$3"|head -3|cat -v)"
    ((PASS++))
}
fail() {
    echo "  FAIL  $1"
    echo "        expected: $(echo "$2"|head -3|cat -v)"
    echo "        got:      $(echo "$3"|head -3|cat -v)"
    ((FAIL++))
}
skip() {
    echo "  SKIP  $1 ($2)"
    ((SKIP++))
}
check() {
    local name="$1" expected="$2" actual="$3" exp_rc="${4:-0}" actual_rc="${5:-0}"
    if [[ "$actual_rc" != "$exp_rc" ]]; then
        fail "$name" "exit $exp_rc" "exit $actual_rc: $actual"
    elif [[ "$actual" == "$expected" ]]; then
        pass "$name" "$expected" "$actual"
    else
        fail "$name" "$expected" "$actual"
    fi
}

# Strip ANSI color codes from preview output
strip_ansi() {
    sed 's/\x1b\[[0-9;]*m//g'
}

# ── helpers ───────────────────────────────────────────────────────────────────
# run zmr, strip ANSI, return stdout; rc stored in $ACTUAL_RC
zmr_run() {
    set +e
    $ZMR "$@" 2>/dev/null > "$TMPOUT"
    ACTUAL_RC=$?
    set -e
    cat "$TMPOUT" | strip_ansi
}

zmr_rc() {
    $ZMR "$@" >/dev/null 2>&1
    echo $?
}

run_category() {
    [[ "$CATEGORY" == "all" || "$CATEGORY" == "$1" ]]
}

# =============================================================================
# 1. BASIC ZOOM TESTS (stdin/stdout, no transforms)
# =============================================================================
if run_category zoom; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. Basic Zoom Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1.1 Zoom into foo() body
expected=$(printf '{\n  printf("hello!\\n");\n}\n')
actual=$(zmr_run -z 'void foo() {_}' -p0 < "$FIXTURES/hello.c")
check "1.1 zoom into void foo() body" "$expected" "$actual" 0 $ACTUAL_RC

# 1.2 Zoom into bar() body
expected=$(printf '{\n  while (i--) {\n    printf("world\\n");\n  }\n}\n')
actual=$(zmr_run -z 'void bar(int i) {_}' -p0 < "$FIXTURES/hello.c")
check "1.2 zoom into void bar(int i) body" "$expected" "$actual" 0 $ACTUAL_RC

# 1.3 Double zoom: bar -> while body
expected=$(printf '{\n    printf("world\\n");\n  }\n')
actual=$(zmr_run -z 'void bar(int i) {_}' -z 'while (i--) {_}' -p0 < "$FIXTURES/hello.c")
check "1.3 double zoom bar->while body" "$expected" "$actual" 0 $ACTUAL_RC

# 1.4 Zoom into main() body
actual=$(zmr_run -z 'int main(int argc, char *argv[]) {_}' -p0 < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'foo();' && pass "1.4 zoom into main() body contains foo()" \
    || fail "1.4 zoom into main() body contains foo()" "foo();" "$actual"

# 1.5 Zoom into else branch
expected=$(printf '{\n    printf("?\\n");\n  }\n')
actual=$(zmr_run -z 'void baz() {_}' -z 'if (g) {} else {_}' -p0 < "$FIXTURES/hello.c")
check "1.5 zoom into else branch" "$expected" "$actual" 0 $ACTUAL_RC

# 1.6 Zoom using stdin (elseif.php)
expected=$(printf '{\n  if ($x) {\n    cmd1();\n  } elseif ($y) {\n    cmd2();\n  } else {\n    cmd3();\n  }\n}\n')
actual=$(zmr_run -z 'function bar() {_}' -p0 < "$FIXTURES/elseif.php")
check "1.6 zoom function bar() from stdin" "$expected" "$actual" 0 $ACTUAL_RC

# 1.7 Zoom elseif - else branch
expected=$(printf '{\n    cmd3();\n  }\n')
actual=$(zmr_run -z 'function bar() {_}' -z 'if ($x) {} elseif ($y) {} else {_}' -p0 < "$FIXTURES/elseif.php")
check "1.7 zoom into else branch of elseif" "$expected" "$actual" 0 $ACTUAL_RC

# 1.8 start/end boundary markers
actual=$(zmr_run -s 'void foo()' -e 'void bar' -p0 < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'printf("hello' && pass "1.8 start/end: foo to bar" \
    || fail "1.8 start/end: foo to bar" "printf(\"hello" "$actual"

# 1.9 zoom + start/end
actual=$(zmr_run -z 'void baz() {_}' -s 'if (g)' -e '} else {' -p0 < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'if (g)' && pass "1.9 zoom+start/end within baz()" \
    || fail "1.9 zoom+start/end within baz()" "if (g)" "$actual"

# 1.10 No-op: file output unchanged without transforms
expected=$(cat "$FIXTURES/hello.c")
actual=$(zmr_run < "$FIXTURES/hello.c")
check "1.10 no-op passthrough (stdin)" "$expected" "$actual" 0 $ACTUAL_RC

# 1.11 No-op with file argument
actual=$(zmr_run "$FIXTURES/hello.c")
check "1.11 no-op passthrough (file arg)" "$expected" "$actual" 0 $ACTUAL_RC

fi  # zoom

# =============================================================================
# 2. BACKTRACKING ZOOM TESTS (stdin/stdout, no transforms)
# =============================================================================
if run_category backtrack; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. Backtracking Zoom Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2.1 Balanced delimiters in pattern don't confuse matching (hello.c)
actual=$(zmr_run -z 'if (strcmp(argv[1], "help") == 0) {_}' -p0 < "$FIXTURES/hello.c")
if echo "$actual" | grep -q 'printf'; then
    pass "2.1 balanced delimiters in pattern"
else
    fail "2.1 balanced delimiters in pattern" "printf" "$actual"
fi

# 2.2 Comment after closing brace doesn't confuse matching (hello.c)
actual=$(zmr_run -z 'void baz() {_}' -p0 < "$FIXTURES/hello.c")
if echo "$actual" | grep -q 'if'; then
    pass "2.2 comment does not confuse brace matching"
else
    fail "2.2 comment does not confuse brace matching" "if" "$actual"
fi

# 2.3 Nested zoom skips intermediate delimiters (hello.c)
actual=$(zmr_run -z 'int main(int argc, char *argv[]) {_}' -z 'if (argc > 1) {_}' -p0 < "$FIXTURES/hello.c")
if echo "$actual" | grep -q 'strcmp'; then
    pass "2.3 nested zoom skips intervening code"
else
    fail "2.3 nested zoom skips intervening code" "strcmp" "$actual"
fi

# ━━ TRUE BACKTRACKING TESTS (using backtrack.php) ━━━━━━━━━━━━━━━━━━━━━━━━━━

# 2.4 Backtrack: Multiple identical function definitions
actual=$(zmr_run -z 'class a {_}' -z 'function foo($x) {_}' -z 'cmd2()' < "$FIXTURES/backtrack.php")
if echo "$actual" | grep -q 'cmd2'; then
    pass "2.4 backtrack: find second foo() with cmd2()"
else
    fail "2.4 backtrack: find second foo() with cmd2()" "cmd2" "$actual"
fi

# 2.5 Backtrack: Comment text doesn't match delimiter pattern
actual=$(zmr_run -z 'class a {_}' -z 'function foo($x) {_}' -z 'cmd1()' < "$FIXTURES/backtrack.php")
if echo "$actual" | grep -q 'cmd1'; then
    pass "2.5 backtrack: skip comment text to find cmd1()"
else
    fail "2.5 backtrack: skip comment text to find cmd1()" "cmd1" "$actual"
fi

# 2.6 Backtrack: Complex nested delimiters
actual=$(zmr_run -z 'class a {_}' -z 'function bar() {_}' -z 'nested_call()' < "$FIXTURES/backtrack.php")
if echo "$actual" | grep -q 'nested_call'; then
    pass "2.6 backtrack: find deeply nested call"
else
    fail "2.6 backtrack: find deeply nested call" "nested_call" "$actual"
fi

# 2.7 Backtrack: Different scope (multiple definitions)
actual=$(zmr_run -z 'function standalone_foo() {_}' < "$FIXTURES/backtrack.php")
if echo "$actual" | grep -q 'echo'; then
    pass "2.7 backtrack: find function in different scope"
else
    fail "2.7 backtrack: find function in different scope" "echo" "$actual"
fi

# 2.8 Backtrack + transform: Verify backtracking finds correct location for modification
actual=$(zmr_run -z 'class a {_}' -z 'function foo($x) {_}' -z 'cmd1()' -r 's/cmd1/MODIFIED/' < "$FIXTURES/backtrack.php")
if echo "$actual" | grep -q 'MODIFIED'; then
    pass "2.8 backtrack + transform: nested code modified"
else
    fail "2.8 backtrack + transform: nested code modified" "MODIFIED" "$actual"
fi

fi  # backtrack

# =============================================================================
# 3. TRANSFORM TESTS (stdin/stdout, no zooms)
# =============================================================================
if run_category transform; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. Transform Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 3.1 Regex replace in zoomed region
actual=$(zmr_run -z 'void foo() {_}' -r 's/hello/HELLO/' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'HELLO' && pass "3.1 regex replace hello->HELLO in foo()" \
    || fail "3.1 regex replace hello->HELLO in foo()" "HELLO" "$actual"
echo "$actual" | grep -q 'void bar' && pass "3.1b rest of file unchanged after foo()" \
    || fail "3.1b rest of file unchanged after foo()" "void bar" "$actual"

# 3.2 Regex global replace whole file
actual=$(zmr_run -r 's/printf/PRINTF/g' < "$FIXTURES/hello.c")
count=$(echo "$actual" | grep -c 'PRINTF' || true)
[[ "$count" -ge 5 ]] && pass "3.2 global regex replace all printf occurrences ($count)" \
    || fail "3.2 global regex replace all printf occurrences" ">=5" "$count"
echo "$actual" | grep -qv 'printf(' && pass "3.2b no lowercase printf remaining" \
    || fail "3.2b no lowercase printf remaining" "" "still has printf"

# 3.3 Literal replace
actual=$(zmr_run -z 'void foo() {_}' -l 's/hello!/goodbye!/' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'goodbye!' && pass "3.3 literal replace hello!->goodbye!" \
    || fail "3.3 literal replace hello!->goodbye!" "goodbye!" "$actual"

# 3.3b Literal replace with Latin-1 input (ASCII) preserves encoding
actual=$(printf 'O + Umlaut = \xd6, currency: xxx\n' | $ZMR -l 's/xxx/CURR/g' 2>&1)
echo "$actual" | od -An -tx1 | grep -q 'd6' && pass "3.3b Latin-1 + ASCII = Latin-1" \
    || fail "3.3b Latin-1 + ASCII = Latin-1" "d6" "$actual"

# 3.3c Literal replace with Latin-1 input (UTF-8) warns
actual=$(printf 'O + Umlaut = \xd6, currency: xxx\n' | $ZMR -l 's/xxx/€/g' 2>&1)
echo "$actual" | grep -q 'WARNING' && pass "3.3c Latin-1 + UTF-8 = UTF-8 (warned)" \
    || fail "3.3c Latin-1 + UTF-8 = UTF-8 (warned)" "WARNING" "$actual"

# 3.4 Literal case-insensitive
actual=$(zmr_run -z 'void foo() {_}' -l 's/Hello/Goodbye/i' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'Goodbye' && pass "3.4 literal case-insensitive replace" \
    || fail "3.4 literal case-insensitive replace" "Goodbye" "$actual"

# 3.5 Multiple transforms applied in order
actual=$(zmr_run -z 'void foo() {_}' -r 's/hello/HELLO/' -r 's/printf/PRINT/' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'PRINT("HELLO' && pass "3.5 multiple transforms applied in order" \
    || fail "3.5 multiple transforms applied in order" 'PRINT("HELLO' "$actual"

# 3.6 Exit code 1 when no match
rc=$(zmr_rc -z 'void foo() {_}' -r 's/NONEXISTENT/X/' < "$FIXTURES/hello.c")
check "3.6 exit code 1 when regex has no match" "" "" 1 $rc

# 3.7 Exit code 0 with no transforms
rc=$(zmr_rc -z 'void foo() {_}' < "$FIXTURES/hello.c")
check "3.7 exit code 0 with no transforms" "" "" 0 $rc

# 3.8 exec transform
actual=$(zmr_run -z 'void foo() {_}' -x 'tr a-z A-Z' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'PRINTF("HELLO' && pass "3.8 exec transform (tr a-z A-Z)" \
    || fail "3.8 exec transform (tr a-z A-Z)" "PRINTF" "$actual"

# 3.9 Delimiter alternates in regex
actual=$(zmr_run -r 's|printf|PRINTF|g' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'PRINTF' && pass "3.9 regex with | delimiter" \
    || fail "3.9 regex with | delimiter" "PRINTF" "$actual"

fi  # transform

# =============================================================================
# 4. TEMPLATE TESTS (stdin/stdout, using template files)
# =============================================================================
if run_category template; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. Template Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 4.1 Template file replaces region
actual=$(zmr_run -z 'void foo() {_}' -t "$FIXTURES/templates/foo_body.c" < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'goodbye' && pass "4.1 template file replaces region" \
    || fail "4.1 template file replaces region" "goodbye" "$actual"
echo "$actual" | grep -q 'void bar' && pass "4.1b rest of file intact" \
    || fail "4.1b rest of file intact" "void bar" "$actual"

# 4.2 Kill region with ':'
actual=$(zmr_run -z 'void foo() {_}' -t ':' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'printf("hello' \
    && fail "4.2 ':' kills region (hello still present)" "" "$actual" \
    || pass "4.2 ':' kills region (hello removed)"
echo "$actual" | grep -q 'void bar' && pass "4.2b rest of file intact after kill" \
    || fail "4.2b rest of file intact after kill" "void bar" "$actual"

# 4.3 Template + regex transform (template rendering)
actual=$(zmr_run -z 'void foo() {_}' -t "$FIXTURES/templates/foo_body.c" -r 's/goodbye/GOODBYE/' < "$FIXTURES/hello.c")
echo "$actual" | grep -q 'GOODBYE' && pass "4.3 template + regex rendering" \
    || fail "4.3 template + regex rendering" "GOODBYE" "$actual"

# 4.4 Template from stdin
TEMPLATE_CONTENT=$(cat "$FIXTURES/templates/foo_body.c")
actual=$(echo "$TEMPLATE_CONTENT" | zmr_run -z 'void foo() {_}' -t - "$FIXTURES/hello.c" 2>/dev/null || true)
echo "$actual" | grep -q 'goodbye' && pass "4.4 template from stdin (-t -)" \
    || skip "4.4 template from stdin (-t -)" "stdin already used"
# 4.5 BOM stripping: Template with BOM should be removed
# Replace a line in hello.c with content from BOM template
actual=$($ZMR -z 'void foo() {_}' -t "$FIXTURES/bom-template.txt" < "$FIXTURES/hello.c" 2>&1)
#echo "$actual" | xxd # hexdump -C 
echo "$actual" | grep -zq $'.\xef\xbb\xbf' && fail "4.5 BOM stripping from template" "DONE" "$actual" \
    || pass "4.5 BOM stripping from template"

fi  # template

# =============================================================================
# 5. FILE I/O TESTS (file input, archive input, no zooms, no transforms)
# =============================================================================
if run_category fileio; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5. File I/O Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 5.1 Read file from filesystem
expected=$(cat "$FIXTURES/hello.c")
actual=$(zmr_run "$FIXTURES/hello.c")
check "5.1 read file from filesystem" "$expected" "$actual" 0 $ACTUAL_RC

# 5.1b Read Latin-1 file (no transform) preserves encoding
actual=$($ZMR "$FIXTURES/latin1-content.txt" 2>&1)
echo "$actual" | od -An -tx1 | grep -q 'd6' && pass "5.1b Latin-1 file preserves encoding" \
    || fail "5.1b Latin-1 file preserves encoding" "d6" "$actual"

# 5.1c Read Latin-1 file + UTF-8 transform warns
actual=$($ZMR -r 's/currency/€/g' "$FIXTURES/latin1-content.txt" 2>&1)
echo "$actual" | grep -q 'WARNING' && pass "5.1c Latin-1 + UTF-8 = UTF-8 (warned)" \
    || fail "5.1c Latin-1 + UTF-8 = UTF-8 (warned)" "WARNING" "$actual"

# 5.2 Read member from tar archive (stdout)
expected=$(printf 'function hello() {\n    // TODO: improve this\n    console.log("hello world");\n}\n\nfunction goodbye() {\n    console.log("goodbye");\n}\n')
actual=$(zmr_run -a "$FIXTURES/test.tar.gz" src/main.js)
check "5.2 read member from tar archive" "$expected" "$actual" 0 $ACTUAL_RC

# 5.3 Read member from zip archive (stdout)
actual=$(zmr_run -a "$FIXTURES/test.zip" src/main.js)
check "5.3 read member from zip archive" "$expected" "$actual" 0 $ACTUAL_RC

# 5.4 Read config.ini from archive
expected=$(printf '[settings]\ndebug=true\nversion=1.0\nname=old_name\n')
actual=$(zmr_run -a "$FIXTURES/test.tar.gz" config.ini)
check "5.4 read config.ini from tar archive" "$expected" "$actual" 0 $ACTUAL_RC

# 5.5 readme.txt from archive (should not be changed by any test)
expected="This file should not be changed."
actual=$(zmr_run -a "$FIXTURES/test.tar.gz" readme.txt)
check "5.5 read readme.txt from tar archive" "$expected" "$actual" 0 $ACTUAL_RC

# 5.6 Error: missing archive member
rc=$(zmr_rc -a "$FIXTURES/test.tar.gz" nonexistent.txt 2>/dev/null)
check "5.6 exit code 2 for missing archive member" "" "" 2 $rc

fi  # fileio

# =============================================================================
# 6. IN-PLACE FILE I/O TESTS
# =============================================================================
if run_category inplace; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "6. In-Place File I/O Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TMPDIR_T=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T"' EXIT

# 6.1 In-place edit: filesystem file
cp "$FIXTURES/hello.c" "$TMPDIR_T/hello.c"
$ZMR -z 'void foo() {_}' -r 's/hello/HELLO/' "$TMPDIR_T/hello.c" -i
grep -q 'HELLO' "$TMPDIR_T/hello.c" && pass "6.1 in-place file edit modifies file" \
    || fail "6.1 in-place file edit modifies file" "HELLO" "$(cat "$TMPDIR_T/hello.c")"
grep -q 'void bar' "$TMPDIR_T/hello.c" && pass "6.1b in-place: rest of file intact" \
    || fail "6.1b in-place: rest of file intact" "void bar" "$(cat "$TMPDIR_T/hello.c")"

# 6.1c In-place Latin-1 (ASCII transform) preserves encoding
cp "$FIXTURES/latin1-content.txt" "$TMPDIR_T/latin1-c.txt"
$ZMR -r 's/currency/CURR/' "$TMPDIR_T/latin1-c.txt" -i
od -An -tx1 "$TMPDIR_T/latin1-c.txt" | grep -q 'd6' && pass "6.1c Latin-1 in-place (ASCII)" \
    || fail "6.1c Latin-1 in-place (ASCII)" "d6"

# 6.1d In-place Latin-1 (UTF-8 transform) warns
cp "$FIXTURES/latin1-content.txt" "$TMPDIR_T/latin1-d.txt"
$ZMR -r 's/currency/€/g' "$TMPDIR_T/latin1-d.txt" -i 2>&1 | grep -q 'WARNING' && \
    pass "6.1d Latin-1 in-place (UTF-8)" || fail "6.1d Latin-1 in-place (UTF-8)" "WARNING"

# 6.2 In-place with backup suffix
cp "$FIXTURES/hello.c" "$TMPDIR_T/hello2.c"
$ZMR -z 'void foo() {_}' -r 's/hello/HELLO/' -i.bak "$TMPDIR_T/hello2.c"
[[ -f "$TMPDIR_T/hello2.c.bak" ]] && pass "6.2 backup file created" \
    || fail "6.2 backup file created" "hello2.c.bak exists" "not found"
grep -q 'printf("hello' "$TMPDIR_T/hello2.c.bak" && pass "6.2b backup has original content" \
    || fail "6.2b backup has original content" 'printf("hello' "$(cat "$TMPDIR_T/hello2.c.bak")"
grep -q 'HELLO' "$TMPDIR_T/hello2.c" && pass "6.2c modified file has new content" \
    || fail "6.2c modified file has new content" "HELLO" "$(cat "$TMPDIR_T/hello2.c")"

# 6.3 In-place edit: tar archive member
cp "$FIXTURES/test.tar.gz" "$TMPDIR_T/test.tar.gz"
$ZMR -a "$TMPDIR_T/test.tar.gz" -z 'function hello() {_}' -r 's/TODO/DONE/' src/main.js -i
CONTENT=$(python3 -c "
import tarfile
with tarfile.open('$TMPDIR_T/test.tar.gz','r:gz') as tf:
    print(tf.extractfile('src/main.js').read().decode(), end='')
")
echo "$CONTENT" | grep -q 'DONE' && pass "6.3 in-place tar archive edit" \
    || fail "6.3 in-place tar archive edit" "DONE" "$CONTENT"
echo "$CONTENT" | grep -qv 'TODO' && pass "6.3b TODO replaced in tar" \
    || fail "6.3b TODO replaced in tar" "no TODO" "$CONTENT"

# 6.4 In-place edit: zip archive member
cp "$FIXTURES/test.zip" "$TMPDIR_T/test.zip"
$ZMR -a "$TMPDIR_T/test.zip" -r 's/old_name/new_name/' config.ini -i
CONTENT=$(python3 -c "
import zipfile
with zipfile.ZipFile('$TMPDIR_T/test.zip') as zf:
    print(zf.read('config.ini').decode(), end='')
")
echo "$CONTENT" | grep -q 'new_name' && pass "6.4 in-place zip archive edit" \
    || fail "6.4 in-place zip archive edit" "new_name" "$CONTENT"

# 6.5 Unmodified archive member stays intact
CONTENT=$(python3 -c "
import tarfile
with tarfile.open('$TMPDIR_T/test.tar.gz','r:gz') as tf:
    print(tf.extractfile('readme.txt').read().decode(), end='')
")
echo "$CONTENT" | grep -q 'should not be changed' && pass "6.5 unmodified archive member unchanged" \
    || fail "6.5 unmodified archive member unchanged" "should not be changed" "$CONTENT"

fi  # inplace

# =============================================================================
# 7. COMBINED TESTS (real-world use cases)
# =============================================================================
if run_category combined; then
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "7. Combined Tests (real-world)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

TMPDIR_T2=$(mktemp -d)
trap 'rm -rf "$TMPDIR_T2"' EXIT

# 7.1 Zoom + transform + in-place file
cp "$FIXTURES/hello.c" "$TMPDIR_T2/hello.c"
$ZMR -z 'void bar(int i) {_}' -z 'while (i--) {_}' -r 's/world/WORLD/' "$TMPDIR_T2/hello.c" -i
grep -q 'WORLD' "$TMPDIR_T2/hello.c" && pass "7.1 zoom+transform+inplace: world->WORLD in while body" \
    || fail "7.1 zoom+transform+inplace: world->WORLD in while body" "WORLD" "$(cat "$TMPDIR_T2/hello.c")"
grep -q 'printf("hello' "$TMPDIR_T2/hello.c" && pass "7.1b zoom+inplace: other regions unchanged" \
    || fail "7.1b zoom+inplace: other regions unchanged" 'printf("hello' "$(cat "$TMPDIR_T2/hello.c")"

# 7.2 Zoom + template + in-place file
cp "$FIXTURES/hello.c" "$TMPDIR_T2/hello2.c"
$ZMR -z 'void foo() {_}' -t "$FIXTURES/templates/foo_body.c" "$TMPDIR_T2/hello2.c" -i
grep -q 'goodbye' "$TMPDIR_T2/hello2.c" && pass "7.2 zoom+template+inplace: template applied" \
    || fail "7.2 zoom+template+inplace: template applied" "goodbye" "$(cat "$TMPDIR_T2/hello2.c")"

# 7.3 Archive: zoom + transform + in-place
cp "$FIXTURES/test.tar.gz" "$TMPDIR_T2/t.tar.gz"
$ZMR -a "$TMPDIR_T2/t.tar.gz" -z 'function hello() {_}' -r 's/TODO/FIXED/' -r 's/improve/IMPROVE/' src/main.js -i
CONTENT=$(python3 -c "
import tarfile
with tarfile.open('$TMPDIR_T2/t.tar.gz','r:gz') as tf:
    print(tf.extractfile('src/main.js').read().decode(), end='')
")
echo "$CONTENT" | grep -q 'FIXED' && pass "7.3 archive+zoom+transform+inplace (FIXED)" \
    || fail "7.3 archive+zoom+transform+inplace" "FIXED" "$CONTENT"
echo "$CONTENT" | grep -q 'IMPROVE' && pass "7.3b archive: second transform applied" \
    || fail "7.3b archive: second transform applied" "IMPROVE" "$CONTENT"
echo "$CONTENT" | grep -q 'function goodbye' && pass "7.3c archive: goodbye() unchanged" \
    || fail "7.3c archive: goodbye() unchanged" "function goodbye" "$CONTENT"

# 7.4 Archive: modify multiple members
cp "$FIXTURES/test.tar.gz" "$TMPDIR_T2/t2.tar.gz"
$ZMR -a "$TMPDIR_T2/t2.tar.gz" -r 's/old_name/new_name/' config.ini -i
$ZMR -a "$TMPDIR_T2/t2.tar.gz" -r 's/1\.0/2.0/' config.ini -i
CONTENT=$(python3 -c "
import tarfile
with tarfile.open('$TMPDIR_T2/t2.tar.gz','r:gz') as tf:
    print(tf.extractfile('config.ini').read().decode(), end='')
")
echo "$CONTENT" | grep -q 'new_name' && pass "7.4 archive: sequential in-place edits (name)" \
    || fail "7.4 archive: sequential in-place edits" "new_name" "$CONTENT"
echo "$CONTENT" | grep -q '2.0' && pass "7.4b archive: sequential in-place edits (version)" \
    || fail "7.4b archive: sequential in-place edits (version)" "2.0" "$CONTENT"

# 7.5 start/end + transform
actual=$(zmr_run -s '// section-start' -e '// section-end' -r 's/getItems/getElements/' < "$FIXTURES/sample.php")
echo "$actual" | grep -q 'getElements' && pass "7.5 start/end+transform: rename in section" \
    || fail "7.5 start/end+transform: rename in section" "getElements" "$actual"
echo "$actual" | grep -q 'function other' && pass "7.5b start/end+transform: outside section unchanged" \
    || fail "7.5b start/end+transform: outside section unchanged" "function other" "$actual"

# 7.6 XML boundary markers
actual=$(zmr_run -s '<a>' -e '</a>' -s '<a>' -e '</a>' -p0 < "$FIXTURES/test.xml")
echo "$actual" | grep -q '<b>' && pass "7.6 XML boundary markers: inner content captured" \
    || fail "7.6 XML boundary markers" "<b>" "$actual"

fi  # combined

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
TOTAL=$((PASS + FAIL + SKIP))
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped / $TOTAL total"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1
