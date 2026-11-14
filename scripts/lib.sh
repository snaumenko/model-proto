# Shared helpers for the three check.sh scripts.
# Tool locations can be overridden from the environment.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QUINT="${QUINT:-$ROOT/node_modules/.bin/quint}"
INTENT="${INTENT:-$( [ -x "$ROOT/tools/bin/intent" ] && echo "$ROOT/tools/bin/intent" || echo intent )}"
ALLIUM="${ALLIUM:-allium}"
ALLOY_JAR="${ALLOY_JAR:-$ROOT/tools/alloy.jar}"
# The simulator's default Rust backend is downloaded on first use; the
# TypeScript backend needs no download. Override with QUINT_BACKEND=rust.
QUINT_BACKEND="${QUINT_BACKEND:-typescript}"

FAILED=0
LOG="$(mktemp)"

# expect <pass|fail> "<label>" <command...>
# pass: the command must succeed.  fail: the command must report a problem.
expect() {
  local want="$1" label="$2"; shift 2
  local got=pass
  "$@" >"$LOG" 2>&1 || got=fail
  if [ "$got" = "$want" ]; then
    printf '  ok    %s\n' "$label"
  else
    printf '  WRONG %s (expected %s, got %s)\n' "$label" "$want" "$got"
    sed 's/^/        | /' "$LOG" | grep -v JAVA_TOOL_OPTIONS | tail -15
    FAILED=1
  fi
}

# expect_report "<label>" "<pattern>" <command...>
# The command must fail AND say why: its output has to match the pattern.
# This keeps a crashed tool from being counted as a detected problem.
expect_report() {
  local label="$1" pattern="$2"; shift 2
  if "$@" >"$LOG" 2>&1; then
    printf '  WRONG %s (expected a reported problem, but the command passed)\n' "$label"; FAILED=1
  elif grep -Eq "$pattern" "$LOG"; then
    printf '  ok    %s\n' "$label"
  else
    printf '  WRONG %s (the command failed, but not with /%s/)\n' "$label" "$pattern"
    sed 's/^/        | /' "$LOG" | grep -v JAVA_TOOL_OPTIONS | tail -15
    FAILED=1
  fi
}

# Alloy exits 0 either way, so read the verdict from its result line:
# UNSAT = no counterexample / no instance, SAT = one was found.
alloy_verdict() { java -jar "$ALLOY_JAR" exec -f -t text -o "$3" -c "$2" "$1" 2>&1 | tr -d '\b' | awk -v c="$2" '$3 == c { print $NF }'; }
alloy_holds()   { [ "$(alloy_verdict "$@")" = UNSAT ]; }
alloy_finds()   { [ "$(alloy_verdict "$@")" = SAT ]; }

section() { printf '\n%s\n' "$1"; }
finish()  { rm -f "$LOG"; [ "$FAILED" = 0 ] && echo && echo "All results as expected." || { echo; echo "Some results were not as expected."; exit 1; }; }
