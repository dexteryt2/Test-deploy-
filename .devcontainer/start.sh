#!/bin/bash
# Runs on every postCreateCommand / postAttachCommand.
set -uo pipefail

XRAY_LOG=/tmp/xray.log
LINK_FILE=/tmp/nikvpn-link.txt
TEST_LOG=/tmp/xray-config-test.log

# Clear stale state from a previous attach so a dead link never looks live.
rm -f "$LINK_FILE"
tmux kill-session -t nikvpn 2>/dev/null || true

echo "[NikVPN] Validating Xray config before starting..."
if ! /usr/local/bin/xray run -test -c /etc/xray/config.json > "$TEST_LOG" 2>&1; then
    echo "[NikVPN] Xray config is INVALID — not starting. Details:"
    cat "$TEST_LOG"
    bash /usr/local/bin/debug.sh
    exit 1
fi
echo "[NikVPN] Config OK."

tmux new-session -d -s nikvpn
tmux send-keys -t nikvpn "/usr/local/bin/xray run -c /etc/xray/config.json &>${XRAY_LOG}" Enter

echo "[NikVPN] Waiting for Xray to bind :443..."
UP=0
for i in $(seq 1 15); do
    if ss -ltn 2>/dev/null | grep -q ':443 '; then
        UP=1
        break
    fi
    sleep 1
done

if [ "$UP" -eq 1 ]; then
    echo "[NikVPN] Xray is listening on :443 — publishing links."
    show-link.sh

    # Serve only /tmp/nikvpn-sub/sub, from its own directory, so the
    # subscription server doesn't expose anything else under /tmp.
    tmux new-window -t nikvpn -n subserver
    tmux send-keys -t nikvpn:subserver \
      "cd /tmp/nikvpn-sub && python3 -m http.server 8080 --bind 0.0.0.0" Enter
else
    echo "[NikVPN] Xray did NOT bind :443 within 15s. NOT publishing a link (it would be dead)."
    echo "[NikVPN] Check /tmp/nikvpn-debug.txt for the reason."
fi

# Always write a fresh debug snapshot, success or failure, so an external
# orchestrator (the Actions workflow, or you manually) can see exactly what
# happened without guessing.
bash /usr/local/bin/debug.sh

tmux new-window -t nikvpn -n keepalive
tmux send-keys -t nikvpn:keepalive "while true; do curl -s --max-time 5 https://github.com/ -o /dev/null; sleep 180; done" Enter
echo "[NikVPN] Done. tmux session: nikvpn (attach with: tmux attach -t nikvpn)"
