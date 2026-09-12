#!/bin/sh
set -e

# NOTE: XTLS/Xray-core marks EVERY GitHub release as "Pre-release" (this is
# intentional on their end, not a mistake). The GitHub API's /releases/latest
# endpoint explicitly excludes pre-releases and drafts, so it 404s for this
# repo — meaning the old code here silently fell through to the hardcoded
# fallback on every single build, forever pinning an old version without
# anyone noticing. Fetching the full /releases list (newest first) instead
# actually gets the current version.
echo "[NikVPN] Resolving latest Xray-core release..."
LATEST=$(curl -fsSL "https://api.github.com/repos/XTLS/Xray-core/releases" | grep -m1 '"tag_name"' | cut -d'"' -f4)

if [ -z "$LATEST" ]; then
    echo "[NikVPN] Could not resolve latest release (API rate-limited?). Using pinned fallback."
    LATEST="v26.7.28"
fi

TMPDIR="$(mktemp -d)"

echo "[NikVPN] Downloading Xray ${LATEST}..."
curl -fsSL "https://github.com/XTLS/Xray-core/releases/download/${LATEST}/Xray-linux-64.zip" -o "${TMPDIR}/xray.zip"
unzip -q "${TMPDIR}/xray.zip" -d "${TMPDIR}"
install -m 755 "${TMPDIR}/xray" /usr/local/bin/xray

echo "[NikVPN] Downloading GeoIP..."
curl -fsSL "https://github.com/v2fly/geoip/releases/latest/download/geoip.dat" -o /usr/local/bin/geoip.dat

echo "[NikVPN] Downloading GeoSite..."
curl -fsSL "https://github.com/v2fly/domain-list-community/releases/latest/download/dlc.dat" -o /usr/local/bin/geosite.dat

UUID=$(uuidgen)
VMESS_UUID=$(uuidgen)
TROJAN_PASS=$(openssl rand -hex 16)
SS_KEY=$(openssl rand -base64 16)

sed -i "s/PLACEHOLDER_VLESS_UUID/${UUID}/g" /etc/xray/config.json
sed -i "s/PLACEHOLDER_VMESS_UUID/${VMESS_UUID}/g" /etc/xray/config.json
sed -i "s/PLACEHOLDER_TROJAN_PASS/${TROJAN_PASS}/g" /etc/xray/config.json
sed -i "s#PLACEHOLDER_SS_KEY#${SS_KEY}#g" /etc/xray/config.json

# Persist creds so show-link.sh can build client links without re-parsing
# four different JSON shapes out of config.json.
mkdir -p /etc/xray
cat > /etc/xray/creds.env << EOF
VLESS_UUID=${UUID}
VMESS_UUID=${VMESS_UUID}
TROJAN_PASS=${TROJAN_PASS}
SS_METHOD=2022-blake3-aes-128-gcm
SS_KEY=${SS_KEY}
EOF

rm -rf "${TMPDIR}"
echo "[NikVPN] Setup complete. Xray ${LATEST} installed."
echo "[NikVPN] VLESS UUID: ${UUID}"
echo "[NikVPN] VMess UUID: ${VMESS_UUID}"
echo "[NikVPN] Trojan pass: ${TROJAN_PASS}"
echo "[NikVPN] SS key: ${SS_KEY}"
