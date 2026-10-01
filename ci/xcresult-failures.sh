#!/usr/bin/env bash
# Prints failing tests + messages from the newest .xcresult and the newest crash
# report as a GitHub annotation (CI logs aren't always easy to reach).
set -uo pipefail
for R in $(ls -td "${1:-ios/build}"/Logs/Test/*.xcresult 2>/dev/null); do
  failures=$(xcrun xcresulttool get test-results tests --path "$R" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin)
except Exception as e:
    print("could not parse xcresult:", e); sys.exit(0)
def walk(node, test):
    if node.get("nodeType") == "Test Case":
        test = node.get("name", test)
    if node.get("nodeType") == "Failure Message":
        print(f"{test}: {node.get(\"name\", \"\")}")
    for child in node.get("children", []) or []:
        walk(child, test)
for n in data.get("testNodes", []):
    walk(n, "")
' | head -n 30)
  [ -n "$failures" ] && out="${out}
== $(basename "$R")
${failures}"
done
for crash in $(ls -t ~/Library/Logs/DiagnosticReports/QuickBite* 2>/dev/null | head -2); do
  summary=$(python3 - "$crash" <<'PY'
import json, sys
text = open(sys.argv[1]).read()
body = json.loads(text[text.index("\n") + 1:])  # .ips = header line + JSON body
exc = body.get("exception", {})
print("exception:", exc.get("type"), exc.get("signal"), body.get("termination", {}).get("indicator"))
asi = body.get("asi") or {}
for k, v in asi.items():
    print("asi:", k, " | ".join(v) if isinstance(v, list) else v)
images = body.get("usedImages", [])
thread = body["threads"][body.get("faultingThread", 0)]
for i, f in enumerate(thread.get("frames", [])[:30]):
    img = images[f["imageIndex"]].get("name", "?") if f.get("imageIndex", -1) < len(images) else "?"
    print(f"{i:2d} {img:28.28s} {f.get('symbol', '?')} {('+' + str(f.get('symbolLocation'))) if 'symbolLocation' in f else ''} {f.get('sourceFile', '')}:{f.get('sourceLine', '')}")
PY
)
  out="${out}
----- crash $(basename "$crash") -----
${summary}"
done
[ -z "$out" ] && out="no xcresult failures or crash reports found"
echo "$out"
encoded=$(printf '%s' "$out" | sed 's/%/%25/g' | awk 'BEGIN{ORS="%0A"} {print}')
echo "::error title=${2:-Test failure details}::${encoded}"
