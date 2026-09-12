#!/bin/bash
# Tests the Codespace container's own bandwidth to the nearest Ookla
# server (Azure/GitHub's datacenter link, NOT your connection in Iran).
#
# This answers ONE question: is the container itself fast? If this
# comes back slow, the bottleneck is the Codespace/Azure side and no
# amount of client-side config tuning will fix it. If this comes back
# fast but you're still slow from your phone, the bottleneck is
# somewhere between the tunnel and your ISP — that's what the
# dx-probe step (see /usr/local/bin/rank-configs.py) is for, run on
# YOUR device, not in here.
#
# Usage: gh codespace ssh -c <name> -- speedtest.sh
echo "[NikVPN] Testing the Codespace container's own bandwidth (not your Iran path)..."
python3 -m speedtest --secure
