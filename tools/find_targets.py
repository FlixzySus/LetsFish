#!/usr/bin/env python3
"""
Scan an Il2CppDumper `dump.cs` for classes/methods that look like the hook
targets in src/Targets.h and print suggested HookTarget lines.

    python3 tools/find_targets.py dump.cs            # all features
    python3 tools/find_targets.py dump.cs bite       # one keyword group

Nothing here is authoritative — read the surrounding code in dump.cs (or the
decompiled IL2CPP in IDA/Ghidra using the RVA) before trusting a candidate.
"""
import re
import sys
from collections import defaultdict

# feature key -> (class keywords, method keywords, kind)
GROUPS = {
    "autocatch":      (["reel", "minigame", "catch", "tension", "fight"],
                       ["success", "issuccess", "iswon", "canlose", "canfishbelost", "haswon"], "HK_RETURN_TRUE"),
    "instantbite":    (["bite", "wait", "spawn", "timer"],
                       ["getwaittime", "waittime", "delay", "bitetime", "timetobite", "gettime"], "HK_RETURN_ZERO_F"),
    "notension":      (["tension", "line", "rod"],
                       ["shouldbreak", "isbroken", "break", "snap", "applydamage", "damage"], "HK_RETURN_FALSE"),
    "noescape":       (["fish", "escape", "hook"],
                       ["tryescape", "escape", "canescape", "unhook", "lost"], "HK_RETURN_FALSE"),
    "bot.controller": (["fishing", "controller", "gameplay", "session"],
                       ["update", "tick"], "HK_CAPTURE_THIS"),
    "bot.cast":       (["fishing", "controller", "gameplay"],
                       ["cast", "throw", "startfishing"], "HK_RESOLVE_ONLY"),
    "bot.reel":       (["fishing", "controller", "gameplay"],
                       ["reel", "pull", "strike"], "HK_RESOLVE_ONLY"),
    "fishesp.capture":(["fish", "bite", "hooked", "catch"],
                       ["initialize", "init", "setup", "onbite", "setfish", ".ctor"], "HK_CAPTURE_THIS"),
    "unlocklocations":(["location", "map", "region", "fishery", "level"],
                       ["isunlocked", "get_isunlocked", "islocked", "get_islocked", "isavailable"], "HK_RETURN_TRUE"),
    "cosmetics":      (["skin", "cosmetic", "lure", "rod", "item", "shop"],
                       ["isowned", "get_isowned", "ispurchased", "get_owned", "hasitem"], "HK_RETURN_TRUE"),
    "noads":          (["ad", "ads", "advert", "ironsource", "applovin", "admob"],
                       ["showinterstitial", "showad", "showrewarded", "show"], "HK_NOP"),
    "dev":            (["cheat", "debug", "dev", "god", "hack"],
                       [], "DEV"),
}

CLASS_RE = re.compile(r"^(?:public|internal|private)?\s*(?:static\s+|abstract\s+|sealed\s+)*(?:class|struct)\s+([\w`<>]+)")
NS_RE = re.compile(r"^// Namespace: (.*)$")
RVA_RE = re.compile(r"// RVA: (0x[0-9A-Fa-f]+) Offset: (0x[0-9A-Fa-f]+)")
METHOD_RE = re.compile(r"^\s*(?:public|internal|private|protected)?\s*(?:static\s+|virtual\s+|override\s+|abstract\s+)*([\w<>\[\],.`]+)\s+([\w.`<>]+)\((.*)\)\s*\{?\s*\}?")


def parse(path):
    """Yield (namespace, class, return_type, method, argc, rva) tuples."""
    ns, cls, rva = "", None, None
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            m = NS_RE.match(line)
            if m:
                ns = m.group(1).strip()
                continue
            m = CLASS_RE.match(line)
            if m:
                cls = m.group(1)
                continue
            m = RVA_RE.search(line)
            if m:
                rva = m.group(1)
                continue
            m = METHOD_RE.match(line)
            if m and cls and rva:
                ret, name, params = m.group(1), m.group(2), m.group(3).strip()
                argc = 0 if not params else params.count(",") + 1
                yield ns, cls, ret, name, argc, rva
                rva = None


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    only = sys.argv[2].lower() if len(sys.argv) > 2 else None
    hits = defaultdict(list)
    for ns, cls, ret, name, argc, rva in parse(sys.argv[1]):
        lc, ln = cls.lower(), name.lower()
        for feat, (ckw, mkw, kind) in GROUPS.items():
            if only and only not in feat:
                continue
            if not any(k in lc for k in ckw):
                continue
            if mkw and not any(k in ln for k in mkw):
                continue
            hits[feat].append((ns, cls, ret, name, argc, rva, kind))

    for feat, rows in hits.items():
        print(f"\n// ===== {feat} ({len(rows)} candidates) =====")
        for ns, cls, ret, name, argc, rva, kind in rows[:40]:
            if kind == "DEV":
                print(f"//   {ns}.{cls}::{name}({argc}) -> {ret}   RVA {rva}")
            else:
                print(f'    {{ "{feat}", "{ns}", "{cls}", "{name}", {argc}, {kind} }},  // {ret}  RVA {rva}')
        if len(rows) > 40:
            print(f"//   ... {len(rows) - 40} more")
    if not hits:
        print("no candidates — check the file is an Il2CppDumper dump.cs")


if __name__ == "__main__":
    main()
