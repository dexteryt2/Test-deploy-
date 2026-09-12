#!/bin/bash
# Builds a client link for every inbound in config.json and writes a
# base64 subscription file, served over HTTPS via the codespace's own
# GitHub-forwarded port 8080 (same edge that already TLS-terminates 443).
#
# THE ACTUAL CONSTRAINT THIS FILE WORKS AROUND, READ THIS FIRST:
#   Codespaces port forwarding proxies HTTP(S)/WebSocket/HTTP2 traffic —
#   it does not tunnel arbitrary raw TCP, and it does not forward UDP at
#   all. That's the one fact that determines what's actually possible
#   here, not "protocol" or "security" in the abstract:
#     - Every inbound below rides on ws / xhttp / grpc / httpupgrade —
#       all HTTP-based — because those are the only transports that
#       survive the tunnel. Plain "tcp" transport would connect-and-die.
#     - VLESS/Trojan-Reality is NOT included: Reality performs its own
#       raw TLS handshake against the client, which requires the server
#       to see the real TLS bytes. Codespaces terminates TLS upstream of
#       the container, so by the time traffic reaches Xray here it's
#       already plaintext HTTP — there is no TLS handshake left for
#       Reality to perform. This isn't a config gap, it's structural:
#       Reality cannot work behind any TLS-terminating tunnel/CDN,
#       Codespaces included.
#     - Hysteria2 and WireGuard need UDP, which Codespaces never
#       forwards. Also structural, not a config gap.
#     - "Different addresses/IPs" (the Cloudflare fragment trick) has no
#       equivalent here: *.app.github.dev is one dynamic per-codespace
#       tunnel, not an anycast network with swappable edge IPs.
#   So the real matrix is: {vless, vmess, trojan} x {ws, xhttp, grpc,
#   httpupgrade} = 12, plus shadowsocks x {ws, httpupgrade} = 2 (with a
#   caveat below) = 14 total. That's the honest ceiling for this
#   specific setup, not ~200 — most of the combinations you're picturing
#   (reality, tcp, extra IPs) are variables that don't actually exist in
#   a Codespaces-tunneled deployment; padding with fake variations of the
#   14 that do work would just be duplicate links, not new configs.
#
# SHADOWSOCKS CAVEAT: the ss:// URI format (SIP002) has no field for
# declaring a websocket/httpupgrade transport the way vless/vmess/trojan
# links do with &type=ws. A client that only understands the standard
# ss:// scheme will ignore that these need a transport and try a plain
# TCP connect, which fails — this is almost certainly why SS didn't ping
# for you. Xray-core-aware clients (v2rayNG, NekoBox, Hiddify, PattNG)
# support importing a full raw outbound JSON instead of a bare link; this
# script writes those JSON files too so you have a working import path.

CONFIG="/etc/xray/config.json"
CREDS="/etc/xray/creds.env"
SUB_DIR="/tmp/nikvpn-sub"
SUB_FILE="${SUB_DIR}/sub"
LINK_FILE="/tmp/nikvpn-link.txt"

if [ ! -f "$CREDS" ]; then
    echo "[NikVPN] Error: ${CREDS} not found (setup.sh didn't run?)."
    exit 1
fi
# shellcheck disable=SC1090
source "$CREDS"

if ! ss -ltn 2>/dev/null | grep -q ':443 '; then
    echo "[NikVPN] Error: nothing is listening on :443 — refusing to publish links."
    echo "[NikVPN] Run debug.sh for details."
    exit 1
fi

host_for() { echo "${CODESPACE_NAME}-$1.app.github.dev"; }

mkdir -p "$SUB_DIR"

build_vless() { # transport port
    local transport="$1" port="$2" host tag
    host=$(host_for "$port"); tag="vless-${transport}"
    case "$transport" in
        xhttp)       echo "vless://${VLESS_UUID}@${host}:443?encryption=none&security=tls&sni=${host}&host=${host}&fp=chrome&type=xhttp&mode=stream-up&path=%2F${tag}#nikvpn-${tag}" ;;
        ws)          echo "vless://${VLESS_UUID}@${host}:443?encryption=none&security=tls&sni=${host}&host=${host}&fp=chrome&type=ws&path=%2F${tag}#nikvpn-${tag}" ;;
        grpc)        echo "vless://${VLESS_UUID}@${host}:443?encryption=none&security=tls&sni=${host}&fp=chrome&type=grpc&serviceName=${tag}&mode=gun#nikvpn-${tag}" ;;
        httpupgrade) echo "vless://${VLESS_UUID}@${host}:443?encryption=none&security=tls&sni=${host}&host=${host}&fp=chrome&type=httpupgrade&path=%2F${tag}#nikvpn-${tag}" ;;
    esac
}

build_vmess() { # transport port
    local transport="$1" port="$2" host tag json
    host=$(host_for "$port"); tag="vmess-${transport}"
    case "$transport" in
        ws)          json=$(jq -nc --arg add "$host" --arg id "$VMESS_UUID" --arg host "$host" --arg path "/${tag}" --arg ps "nikvpn-${tag}" '{v:"2",ps:$ps,add:$add,port:"443",id:$id,aid:"0",scy:"auto",net:"ws",type:"none",host:$host,path:$path,tls:"tls",sni:$host,fp:"chrome"}') ;;
        xhttp)       json=$(jq -nc --arg add "$host" --arg id "$VMESS_UUID" --arg host "$host" --arg path "/${tag}" --arg ps "nikvpn-${tag}" '{v:"2",ps:$ps,add:$add,port:"443",id:$id,aid:"0",scy:"auto",net:"xhttp",type:"stream-up",host:$host,path:$path,tls:"tls",sni:$host,fp:"chrome"}') ;;
        grpc)        json=$(jq -nc --arg add "$host" --arg id "$VMESS_UUID" --arg host "$host" --arg svc "$tag" --arg ps "nikvpn-${tag}" '{v:"2",ps:$ps,add:$add,port:"443",id:$id,aid:"0",scy:"auto",net:"grpc",type:"gun",path:$svc,tls:"tls",sni:$host,fp:"chrome"}') ;;
        httpupgrade) json=$(jq -nc --arg add "$host" --arg id "$VMESS_UUID" --arg host "$host" --arg path "/${tag}" --arg ps "nikvpn-${tag}" '{v:"2",ps:$ps,add:$add,port:"443",id:$id,aid:"0",scy:"auto",net:"httpupgrade",type:"none",host:$host,path:$path,tls:"tls",sni:$host,fp:"chrome"}') ;;
    esac
    echo "vmess://$(echo -n "$json" | base64 -w0)"
}

build_trojan() { # transport port
    local transport="$1" port="$2" host tag
    host=$(host_for "$port"); tag="trojan-${transport}"
    case "$transport" in
        ws)          echo "trojan://${TROJAN_PASS}@${host}:443?security=tls&sni=${host}&host=${host}&type=ws&path=%2F${tag}&fp=chrome#nikvpn-${tag}" ;;
        xhttp)       echo "trojan://${TROJAN_PASS}@${host}:443?security=tls&sni=${host}&host=${host}&type=xhttp&mode=stream-up&path=%2F${tag}&fp=chrome#nikvpn-${tag}" ;;
        grpc)        echo "trojan://${TROJAN_PASS}@${host}:443?security=tls&sni=${host}&type=grpc&serviceName=${tag}&mode=gun&fp=chrome#nikvpn-${tag}" ;;
        httpupgrade) echo "trojan://${TROJAN_PASS}@${host}:443?security=tls&sni=${host}&host=${host}&type=httpupgrade&path=%2F${tag}&fp=chrome#nikvpn-${tag}" ;;
    esac
}

{
    build_vless  xhttp       443
    build_vless  ws          8005
    build_vless  grpc        8006
    build_vless  httpupgrade 8007
    build_vmess  ws          8880
    build_vmess  xhttp       8008
    build_vmess  grpc        8009
    build_vmess  httpupgrade 8010
    build_trojan ws          8443
    build_trojan xhttp       8011
    build_trojan grpc        8012
    build_trojan httpupgrade 8013
} > "$SUB_FILE.raw"

# --- Shadowsocks: bare links (best-effort — see caveat above) + JSON outbounds ---
SS_HOST_WS=$(host_for 2053)
SS_HOST_HU=$(host_for 8014)
SS_USERINFO=$(echo -n "${SS_METHOD}:${SS_KEY}" | base64 -w0)
{
  echo "ss://${SS_USERINFO}@${SS_HOST_WS}:443?security=tls&sni=${SS_HOST_WS}&host=${SS_HOST_WS}&type=ws&path=%2Fss-ws#nikvpn-ss-ws"
  echo "ss://${SS_USERINFO}@${SS_HOST_HU}:443?security=tls&sni=${SS_HOST_HU}&host=${SS_HOST_HU}&type=httpupgrade&path=%2Fss-httpupgrade#nikvpn-ss-httpupgrade"
} >> "$SUB_FILE.raw"

for variant in "ws 2053" "httpupgrade 8014"; do
    set -- $variant
    transport="$1"; port="$2"
    host=$(host_for "$port")
    jq -n --arg host "$host" --arg method "$SS_METHOD" --arg pass "$SS_KEY" --arg transport "$transport" --arg path "/ss-${transport}" \
      '{outbounds:[{protocol:"shadowsocks",settings:{servers:[{address:$host,port:443,method:$method,password:$pass}]},streamSettings:({network:$transport,security:"tls",sni:$host}+(if $transport=="ws" then {wsSettings:{path:$path}} else {httpupgradeSettings:{path:$path}} end))}]}' \
      > "${SUB_DIR}/ss-${transport}-import.json"
done

echo ""
echo "========================================"
echo "NikVPN - 14 configs (vless/vmess/trojan x ws/xhttp/grpc/httpupgrade, + 2 shadowsocks)"
echo "========================================"
cat "$SUB_FILE.raw"
echo "========================================"
echo "Shadowsocks bare ss:// links above are best-effort (see caveat in this"
echo "script's header). If they don't connect, import these JSON files instead:"
echo "  ${SUB_DIR}/ss-ws-import.json"
echo "  ${SUB_DIR}/ss-httpupgrade-import.json"
echo ""

# Primary link file kept for backward compatibility with start-vpn.yml,
# which reads this single-line file.
build_vless xhttp 443 > "$LINK_FILE"

base64 -w0 "$SUB_FILE.raw" > "$SUB_FILE"

SUB_URL="https://${CODESPACE_NAME}-8080.app.github.dev/sub"
echo "[NikVPN] Subscription (all links, base64) will be served at:"
echo "  ${SUB_URL}"
echo "${SUB_URL}" > /tmp/nikvpn-sub-url.txt

# --- dx-probe targets file ---
# Network conditions from inside this container are Azure/GitHub's, not
# yours in Iran — there is no way to measure "which of these 14 configs
# is best on my ISP" from in here. What we CAN do is hand you a
# dx-probe-ready targets.json with our actual 14 hostnames, so you run
# the real measurement on your own device and rank the sub against it.
# See rank-configs.py (shipped alongside this repo) for the second half.
python3 - "$SUB_DIR/dx-probe-targets.json" << 'PYEOF'
import json, os, sys

ports = {
    "vless-xhttp": 443, "vless-ws": 8005, "vless-grpc": 8006, "vless-httpupgrade": 8007,
    "vmess-ws": 8880, "vmess-xhttp": 8008, "vmess-grpc": 8009, "vmess-httpupgrade": 8010,
    "trojan-ws": 8443, "trojan-xhttp": 8011, "trojan-grpc": 8012, "trojan-httpupgrade": 8013,
    "ss-ws": 2053, "ss-httpupgrade": 8014,
}
codespace = os.environ.get("CODESPACE_NAME", "")
targets = [
    {"name": tag, "host": f"{codespace}-{port}.app.github.dev", "port": 443,
     "protocol": "tls", "tags": [tag.split("-")[0], tag.split("-", 1)[1]]}
    for tag, port in ports.items()
]
doc = {"baseline_target": "vless-xhttp", "targets": targets}
with open(sys.argv[1], "w") as f:
    json.dump(doc, f, indent=2)
PYEOF
echo "[NikVPN] dx-probe targets file (for your local dx-probe/config/targets.json):"
echo "  ${SUB_DIR}/dx-probe-targets.json"
