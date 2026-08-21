#!/usr/bin/env bash

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
CLI="$ROOT/bin/ardour-ci"
TEST_ROOT=$(mktemp -d)
trap 'rm -rf "$TEST_ROOT"' EXIT

pass=0
fail=0

assert_contains() {
    local haystack=$1 needle=$2
    case "$haystack" in
        *"$needle"*) pass=$((pass + 1)) ;;
        *) printf 'expected to find: %s\n' "$needle" >&2; fail=$((fail + 1)) ;;
    esac
}

make_source() {
    local directory=$1
    mkdir -p "$directory"
    git init -q "$directory"
    git -C "$directory" config user.email test@example.invalid
    git -C "$directory" config user.name Test
    printf 'one\n' > "$directory/file"
    git -C "$directory" add file
    git -C "$directory" commit -qm initial
    git -C "$directory" tag v1.0.0
}

SOURCE_ONE="$TEST_ROOT/ardour-one"
SOURCE_TWO="$TEST_ROOT/ardour-two"
WORK="$TEST_ROOT/work"
MOCK_BIN="$TEST_ROOT/mock-bin"
make_source "$SOURCE_ONE"
make_source "$SOURCE_TWO"
SOURCE_ONE=$(cd "$SOURCE_ONE" && pwd -P)
SOURCE_TWO=$(cd "$SOURCE_TWO" && pwd -P)

"$CLI" --work-dir "$WORK" config set-source "$SOURCE_ONE" >/dev/null
output=$("$CLI" --work-dir "$WORK" config show)
assert_contains "$output" "source_path=$SOURCE_ONE"

output=$("$CLI" --work-dir "$WORK" --source "$SOURCE_TWO" config show)
assert_contains "$output" "source_path=$SOURCE_TWO"

output=$("$CLI" --work-dir "$WORK" source status)
assert_contains "$output" "tag=v1.0.0"
assert_contains "$output" "worktree=clean"

printf 'dirty\n' >> "$SOURCE_ONE/file"
output=$("$CLI" --work-dir "$WORK" source status)
assert_contains "$output" "worktree=dirty"

REV=0123456789abcdef0123456789abcdef01234567
mkdir -p "$MOCK_BIN"
printf '#!/usr/bin/env bash\nprintf "    build-stack: %%s\\n" "0123456789abcdef0123456789abcdef01234567"\n' > "$MOCK_BIN/curl"
chmod +x "$MOCK_BIN/curl"
PATH="$MOCK_BIN:$PATH" "$CLI" --work-dir "$WORK" deps sync >/dev/null
output=$(cat "$WORK/build-stack.lock")
assert_contains "$output" "build_stack_rev=$REV"

output=$("$CLI" --work-dir "$WORK" --source "$SOURCE_TWO" --dry-run build 2>&1 || true)
assert_contains "$output" "dependency stack is not built"

STACK="$WORK/stacks/$REV"
mkdir -p "$STACK/gtk/inst/lib/pkgconfig"
printf '%s\n' "$REV" > "$STACK/.built-rev"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "$WAF_LOG"\n' > "$SOURCE_ONE/waf"
chmod +x "$SOURCE_ONE/waf"
git -C "$SOURCE_ONE" add waf file
git -C "$SOURCE_ONE" commit -qm buildable
WAF_LOG="$TEST_ROOT/waf.log"
export WAF_LOG
"$CLI" --work-dir "$WORK" build >/dev/null
FIRST_COMMIT=$(git -C "$SOURCE_ONE" rev-parse HEAD)
test -f "$WORK/builds/$FIRST_COMMIT/metadata" || { printf 'missing first build metadata\n' >&2; exit 1; }
assert_contains "$(cat "$WAF_LOG")" "--arm64"

printf 'next\n' >> "$SOURCE_ONE/file"
git -C "$SOURCE_ONE" add file
git -C "$SOURCE_ONE" commit -qm next
"$CLI" --work-dir "$WORK" build >/dev/null
SECOND_COMMIT=$(git -C "$SOURCE_ONE" rev-parse HEAD)
test "$FIRST_COMMIT" != "$SECOND_COMMIT" || { printf 'source commit did not change\n' >&2; exit 1; }
test -f "$WORK/builds/$SECOND_COMMIT/metadata" || { printf 'missing second build metadata\n' >&2; exit 1; }
assert_contains "$(readlink "$SOURCE_ONE/build")" "$WORK/builds/$SECOND_COMMIT"

if [ "$fail" -ne 0 ]; then
    printf '%s test assertion(s) failed\n' "$fail" >&2
    exit 1
fi
printf '%s assertions passed\n' "$pass"
