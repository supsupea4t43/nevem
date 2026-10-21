#!/usr/bin/env python3
"""Where is the Appats Model Tracker losing models?

Reads live_chart/data.json from supsupea4t43/appats-tracker and, for every
model-at-a-host offering, counts which requirement(s) it fails. The pass rule
mirrors the tracker: Spanish and Catalan both "named" by the maker (langOK in
template.html), and DPA yes/request, EU processing, no training, no retention
and tool calling at the host (Get-Cheapest in refresh.ps1).

Usage: python3 requirement_gaps.py path/to/appats-tracker/live_chart/data.json
"""
import collections
import json
import sys

CHECKS = ("lang", "dpa", "eu", "notrain", "noretain", "tools")


def checks(model, host_flags):
    """Return {check: passes?} for one offering."""
    lg = model.get("lg") or {}
    return {
        "lang": lg.get("es") == "named" and lg.get("ca") == "named",
        "dpa": host_flags["dpa"] in ("yes", "request"),
        "eu": host_flags["eu"] == 1,
        "notrain": host_flags["tr"] == 0,
        "noretain": host_flags["rt"] == 0,
        "tools": host_flags["tl"] == 1,
    }


def main(path):
    data = json.load(open(path, encoding="utf-8"))
    models = data["models"]
    providers = {p[0]: p for p in data["meta"]["providers"]}

    offerings = [(m, pv, checks(m, pv[6])) for m in models for pv in m["pv"]]
    passing = [o for o in offerings if all(o[2].values())]
    print(f"{len(offerings)} offerings across {len(models)} models")
    print(f"pass every requirement: {len(passing)} offerings, "
          f"{len({o[0]['n'] for o in passing})} models\n")

    # Offerings that fail exactly one check: the cheapest data gaps to close.
    only = collections.defaultdict(list)
    for m, pv, c in offerings:
        failed = [k for k in CHECKS if not c[k]]
        if len(failed) == 1:
            only[failed[0]].append((m, pv))
    print("offerings failing ONLY one requirement:")
    for k in CHECKS:
        rows = only.get(k, [])
        print(f"  {k:9s} {len(rows):4d} offerings, {len({m['n'] for m, _ in rows}):3d} models")

    # Language is the one check where the tracker lacks data rather than the
    # host lacking the property, so break it down by maker.
    print("\nfail only on language, by maker (es / ca as the tracker records them):")
    by_maker = collections.defaultdict(lambda: [set(), 0])
    lang_key = {}
    for m, pv in only.get("lang", []):
        lg = m.get("lg") or {}
        by_maker[m["cr"]][0].add(m["n"])
        by_maker[m["cr"]][1] += 1
        lang_key[m["cr"]] = f"{lg.get('es') or 'no data'} / {lg.get('ca') or 'no data'}"
    for maker, (names, n) in sorted(by_maker.items(), key=lambda kv: -kv[1][1]):
        print(f"  {maker:10s} {lang_key[maker]:20s} {len(names):2d} model(s), {n:2d} offerings: "
              f"{', '.join(sorted(names)[:3])}{' ...' if len(names) > 3 else ''}")

    # Would researching DPAs change the chart? Only if the host passes the rest.
    unresolved = {h for h, p in providers.items() if p[4] in ("", "not found")}
    dpa_only = [(m, pv) for m, pv in only.get("dpa", []) if pv[0] in unresolved]
    print(f"\nhosts with DPA 'not checked' or 'not found': {len(unresolved)}")
    print(f"offerings that a DPA for one of them would newly qualify: {len(dpa_only)}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
