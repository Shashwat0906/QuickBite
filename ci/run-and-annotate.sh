#!/usr/bin/env bash
# Runs a build/test command, keeps the full log, and turns the important lines
# into GitHub annotations (visible on the run page and via `gh` / the REST API).
#   ci/run-and-annotate.sh "<title>" <command…>
set -uo pipefail
title="$1"; shift
log="$(mktemp)"
"$@" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}

summary=$(grep -E "Executed [0-9]+ tests?, with [0-9]+ failures?|Test Suite 'All tests' (passed|failed)|\*\* (BUILD|TEST) (SUCCEEDED|FAILED) \*\*|Build complete!" "$log" | tail -n 3 | tr '\n' ' ')
if [ "$status" -eq 0 ]; then
  echo "::notice title=${title}::${summary:-ok}"
else
  # Compiler errors, failing assertions and linker errors — deduplicated, first 60.
  errors=$(grep -E "(error:|: error |XCTAssert|failed \(|Undefined symbol|ld: |\*\* .* FAILED \*\*|fatal error|Fatal error|crash|Crash|Restarting after|unexpected exit|timed out|Thread [0-9]+ Crashed|Testing failed)" "$log" \
    | sed -E 's#^/Users/runner/work/[^/]+/[^/]+/##' | awk '!seen[$0]++' | head -n 50)
  errors="${errors}
----- last lines -----
$(tail -n 45 "$log" | sed -E 's#^/Users/runner/work/[^/]+/[^/]+/##')"
  encoded=$(printf '%s' "$errors" | sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
  echo "::error title=${title} failed::${encoded}"
fi
exit "$status"
