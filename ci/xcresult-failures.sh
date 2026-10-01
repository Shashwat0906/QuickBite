#!/usr/bin/env bash
# Prints failing tests + messages from the newest .xcresult and the newest crash
# report as a GitHub annotation (CI logs aren't always easy to reach).
set -uo pipefail
R=$(ls -td "${1:-ios/build}"/Logs/Test/*.xcresult 2>/dev/null | head -1)
out=""
if [ -n "$R" ]; then
  out=$(xcrun xcresulttool get test-results tests --path "$R" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print("could not parse xcresult:", e); sys.exit(0)
def walk(node, path):
    name = node.get("name", "")
    if node.get("nodeType") == "Failure Message":
        print(f"{path}: {name}")
    for child in node.get("children", []) or []:
        walk(child, f"{path} > {name}" if node.get("nodeType") in ("Test Case",) else (name if node.get("nodeType") == "Test Case" else path))
for n in data.get("testNodes", []):
    walk(n, "")
' | head -n 40)
fi
crash=$(ls -t ~/Library/Logs/DiagnosticReports/QuickBite* 2>/dev/null | head -1)
if [ -n "$crash" ]; then
  out="${out}
----- crash report $(basename "$crash") -----
$(head -c 6000 "$crash")"
fi
[ -z "$out" ] && out="no xcresult failures or crash reports found"
echo "$out"
encoded=$(printf '%s' "$out" | sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
echo "::error title=${2:-Test failure details}::${encoded}"
