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
printf '#!/usr/bin/env bash\nprintf "    build-stack&colon; %%s&NewLine;\n" "0123456789abcdef0123456789abcdef01234567"\n' > "$MOCK_BIN/curl"
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

make_stack_tools() {
    local directory=$1
    mkdir -p "$directory"
    git init -q "$directory"
    git -C "$directory" config user.email test@example.invalid
    git -C "$directory" config user.name Test
    cat > "$directory/x-applearm.sh" <<'EOF'
#!/usr/bin/env bash
set -e
: ${BUILDROOT:?}
: ${SRCDIR:?}
: ${PREFIX=${BUILDROOT}/gtk/inst}
: ${BLDDEP=${BUILDROOT}/gtk/tool}
: ${BUILDD=${BUILDROOT}/gtk/src}
src() { :; }
rm -rf ${PREFIX}
rm -rf ${BUILDD}
rm -rf ${BLDDEP}
mkdir -p ${PREFIX}
mkdir -p ${BUILDD}
mkdir -p ${BLDDEP}
src alpha-1 tar.gz https://example.invalid/alpha.tar.gz
printf 'alpha\n' >> "$STEP_LOG"
src beta-1 tar.gz https://example.invalid/beta.tar.gz
printf 'beta\n' >> "$STEP_LOG"
[ ! -f "$FAIL_BETA" ] || exit 42
src gamma-1 tar.gz https://example.invalid/gamma.tar.gz
printf 'gamma\n' >> "$STEP_LOG"
[ ! -f "$FAIL_GAMMA" ] || exit 43
EOF
    chmod +x "$directory/x-applearm.sh"
    git -C "$directory" add x-applearm.sh
    git -C "$directory" commit -qm stack
}

TOOLS_REPO="$TEST_ROOT/build-tools"
RESUME_WORK="$TEST_ROOT/resume-work"
STEP_LOG="$TEST_ROOT/steps.log"
FAIL_BETA="$TEST_ROOT/fail-beta"
FAIL_GAMMA="$TEST_ROOT/fail-gamma"
export STEP_LOG FAIL_BETA FAIL_GAMMA
make_stack_tools "$TOOLS_REPO"
RESUME_REV=$(git -C "$TOOLS_REPO" rev-parse HEAD)
mkdir -p "$RESUME_WORK"
printf 'build_stack_rev=%s\n' "$RESUME_REV" > "$RESUME_WORK/build-stack.lock"
touch "$FAIL_BETA"
set +e
resume_output=$(ARDOUR_CI_BUILD_STACK_URL="$TOOLS_REPO" "$CLI" --work-dir "$RESUME_WORK" deps build 2>&1)
resume_status=$?
set -e
test "$resume_status" -ne 0 || { printf 'mock dependency build unexpectedly succeeded\n' >&2; exit 1; }
RESUME_STACK="$RESUME_WORK/stacks/$RESUME_REV"
test ! -f "$RESUME_STACK/.built-rev" || { printf 'failed stack was marked ready\n' >&2; exit 1; }
test -f "$RESUME_STACK/.resume/state/001-alpha-1" || { printf 'first checkpoint is missing\n%s\n' "$resume_output" >&2; exit 1; }
test -d "$RESUME_STACK/.resume/snapshots/001-alpha-1" || { printf 'first snapshot is missing\n' >&2; exit 1; }
test ! -f "$RESUME_STACK/.resume/state/002-beta-1" || { printf 'failed step has a checkpoint\n' >&2; exit 1; }

rm "$FAIL_BETA"
touch "$FAIL_GAMMA"
set +e
resume_output=$(ARDOUR_CI_BUILD_STACK_URL="$TOOLS_REPO" "$CLI" --work-dir "$RESUME_WORK" deps build 2>&1)
resume_status=$?
set -e
test "$resume_status" -ne 0 || { printf 'second mock dependency build unexpectedly succeeded\n' >&2; exit 1; }
test -f "$RESUME_STACK/.resume/state/002-beta-1" || { printf 'second checkpoint is missing\n' >&2; exit 1; }
test "$(grep -c '^alpha$' "$STEP_LOG")" -eq 1 || { printf 'completed dependency was rebuilt\n%s\n' "$resume_output" >&2; exit 1; }

sed -i.bak 's/printf '\''beta\\n'\''/printf '\''beta-v2\\n'\''/' "$RESUME_WORK/build-tools/$RESUME_REV/x-applearm.sh"
rm "$FAIL_GAMMA"
ARDOUR_CI_BUILD_STACK_URL="$TOOLS_REPO" "$CLI" --work-dir "$RESUME_WORK" deps build >/dev/null
test -f "$RESUME_STACK/.built-rev" || { printf 'completed stack has no ready marker\n' >&2; exit 1; }
test ! -d "$RESUME_STACK/.resume" || { printf 'resume state survived successful build\n' >&2; exit 1; }
test "$(grep -c '^alpha$' "$STEP_LOG")" -eq 1 || { printf 'unchanged earlier dependency was rebuilt\n' >&2; exit 1; }
test "$(grep -c '^beta$' "$STEP_LOG")" -eq 2 || { printf 'locally modified recipe was not restored\n' >&2; exit 1; }
test "$(grep -c '^beta-v2$' "$STEP_LOG")" -eq 0 || { printf 'locally modified recipe was used\n' >&2; exit 1; }
ready_output=$(ARDOUR_CI_BUILD_STACK_URL="$TOOLS_REPO" "$CLI" --work-dir "$RESUME_WORK" deps build 2>&1)
assert_contains "$ready_output" "dependency stack is ready"
test ! -d "$RESUME_STACK/.resume" || { printf 'ready stack created resume state\n' >&2; exit 1; }

if [ "$fail" -ne 0 ]; then
    printf '%s test assertion(s) failed\n' "$fail" >&2
    exit 1
fi
printf '%s assertions passed\n' "$pass"
