#!/bin/bash
# Single-file diagnostic snapshot. Written every time start.sh runs, so the
# workflow (or you, manually) can always pull one file and see exactly
# where things stand — no more guessing whether it's still building,
# whether Xray crashed, or whether the port never opened.
OUT=/tmp/nikvpn-debug.txt

{
  echo "===== NikVPN Debug Report ====="
  date -u
  echo

  echo "----- user -----"
  whoami; id
  echo

  echo "----- xray binary -----"
  /usr/local/bin/xray version 2>&1 || echo "[missing or broken] /usr/local/bin/xray"
  echo

  echo "----- xray process -----"
  pgrep -af xray 2>/dev/null || echo "no xray process running"
  echo

  echo "----- listening ports -----"
  ss -ltnp 2>&1 || echo "ss unavailable"
  echo

  echo "----- config validation log -----"
  cat /tmp/xray-config-test.log 2>/dev/null || echo "(no config test log yet)"
  echo

  echo "----- xray.log (last 80 lines) -----"
  tail -n 80 /tmp/xray.log 2>/dev/null || echo "(no /tmp/xray.log yet)"
  echo

  echo "----- xray-error.log (last 80 lines) -----"
  tail -n 80 /tmp/xray-error.log 2>/dev/null || echo "(no /tmp/xray-error.log yet)"
  echo

  echo "----- link file -----"
  cat /tmp/nikvpn-link.txt 2>/dev/null || echo "(no link written — Xray is not confirmed up)"
  echo

  echo "----- subscription URL -----"
  cat /tmp/nikvpn-sub-url.txt 2>/dev/null || echo "(no sub URL written yet)"
  echo

  echo "----- sub server process -----"
  pgrep -af "http.server 8080" 2>/dev/null || echo "no sub server process running"
  echo

  echo "----- forwarded ports (best effort) -----"
  gh codespace ports -c "${CODESPACE_NAME:-}" 2>&1 || echo "(gh ports query failed / not available yet)"
} > "$OUT" 2>&1

echo "[NikVPN] Debug report written to $OUT"
