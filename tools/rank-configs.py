#!/usr/bin/env python3
"""rank-configs.py — cross-references a dx-probe report against the
nikvpn-auto subscription and prints the 14 configs best-first.

WHY THIS RUNS ON YOUR OWN MACHINE, NOT INSIDE THE CODESPACE:
Network conditions from inside the Codespace container are Azure/
GitHub's network, not your ISP's. There is no vantage point inside the
container from which "which of these configs is best on my Iran
connection" is even a measurable question. dx-probe has to run where
you actually are.

Standard-library only, same constraint dx-network-profiler and dx-probe
already follow — nothing to pip install.

Usage:
  1. On the Codespace, after `show-link.sh` has run, grab the targets file:
       gh codespace ssh -c <name> -- cat /tmp/nikvpn-sub/dx-probe-targets.json > targets.json
  2. Drop it in as your dx-probe config:
       cp targets.json /path/to/dx-probe/config/targets.json
  3. Run the real scan FROM YOUR OWN DEVICE (phone/laptop on your actual
     Iran connection — Termux works for the phone case):
       cd /path/to/dx-probe && ./dx scan --json > report.json
  4. Rank the sub against it:
       python3 rank-configs.py --report report.json \
           --sub-url https://<codespace>-8080.app.github.dev/sub

Or pass --sub-file if you already have the decoded sub text saved locally.
"""
from __future__ import annotations

import argparse
import base64
import json
import re
import sys
import urllib.request

HOST_PATTERNS = [
    re.compile(r"vless://[^@]+@([^:?/]+)"),
    re.compile(r"trojan://[^@]+@([^:?/]+)"),
    re.compile(r"ss://[^@]+@([^:?/]+)"),
]


def extract_host(link: str) -> str | None:
    if link.startswith("vmess://"):
        try:
            payload = link[len("vmess://"):].split("#")[0]
            data = json.loads(base64.b64decode(payload + "=" * (-len(payload) % 4)))
            return data.get("add")
        except Exception:
            return None
    for pat in HOST_PATTERNS:
        m = pat.search(link)
        if m:
            return m.group(1)
    return None


def load_sub(args) -> list[str]:
    if args.sub_file:
        raw = open(args.sub_file, encoding="utf-8").read().strip()
    elif args.sub_url:
        with urllib.request.urlopen(args.sub_url, timeout=10) as resp:
            raw = resp.read().decode("utf-8").strip()
    else:
        raise SystemExit("pass --sub-url or --sub-file")
    # The served file is base64 of newline-separated links.
    try:
        decoded = base64.b64decode(raw + "=" * (-len(raw) % 4)).decode("utf-8")
        lines = [l for l in decoded.splitlines() if l.strip()]
        if all(extract_host(l) is None for l in lines[:1]):
            raise ValueError
        return lines
    except Exception:
        # Fall back to treating input as already-decoded plain links.
        return [l for l in raw.splitlines() if l.strip()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", required=True, help="dx-probe report.json (dx scan --json)")
    ap.add_argument("--sub-url", help="https://<codespace>-8080.app.github.dev/sub")
    ap.add_argument("--sub-file", help="path to a locally saved copy of the sub content")
    args = ap.parse_args()

    report = json.load(open(args.report, encoding="utf-8"))
    scores_by_host = {}
    for t in report.get("targets", []):
        scores_by_host[t["target"]] = t

    links = load_sub(args)
    ranked = []
    unmatched = []
    for link in links:
        host = extract_host(link)
        # dx-probe's "target" is matched by whatever "host" your
        # targets.json used for that entry — with the file show-link.sh
        # generates, that's the same *.app.github.dev hostname embedded
        # in the link itself, so this direct lookup should hit.
        info = scores_by_host.get(host) if host else None
        if info:
            ranked.append((info.get("score") or -1, info.get("state", "unknown"), host, link, info.get("reasons", [])))
        else:
            unmatched.append((host, link))

    ranked.sort(key=lambda r: r[0], reverse=True)

    print(f"Ranked {len(ranked)}/{len(links)} configs against dx-probe scores for your network:\n")
    for score, state, host, link, reasons in ranked:
        reason_str = f" — {'; '.join(reasons)}" if reasons else ""
        print(f"[{score:5.1f} | {state:8s}] {host}{reason_str}")
        print(f"  {link}\n")

    if unmatched:
        print(f"({len(unmatched)} config(s) had no matching dx-probe target — host mismatch or targets.json wasn't the one show-link.sh generated)")
        for host, link in unmatched:
            print(f"  unmatched host: {host}")


if __name__ == "__main__":
    main()
