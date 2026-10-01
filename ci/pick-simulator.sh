#!/usr/bin/env bash
# Prints the UDID of the newest available iPhone simulator.
xcrun simctl list devices available -j | python3 -c '
import json, sys, re
devices = json.load(sys.stdin)["devices"]
best = None
for runtime, items in devices.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m: continue
    version = (int(m.group(1)), int(m.group(2)))
    for d in items:
        if d["name"].startswith("iPhone") and "Pro Max" not in d["name"]:
            if best is None or version > best[0]:
                best = (version, d["udid"], d["name"])
print(best[1])
print(f"Using {best[2]} iOS {best[0][0]}.{best[0][1]}", file=sys.stderr)
'
