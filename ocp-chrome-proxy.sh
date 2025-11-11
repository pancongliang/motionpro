#!/bin/bash
# Run this script on a Mac to access the OpenShift Console via a SOCKS5 proxy
set -euo pipefail

# ============================================
# 1. Set environment variables
# ============================================

# Ingress domain for Chrome OCP console bookmarks
INGRESS_DOMAIN="apps.ocp.example.com"

# VPN machine SSH access (ensure key-based authentication is set up)
VPN_MACHINE_IP="10.0.79.55"
VPN_MACHINE_USER="root"

# Proxy port for local PC and VPN machine (default: 8899; change only if conflicts occur)
PROXY_PORT="8899"

# Chrome executable path (default for macOS; modify if installed elsewhere)
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


# ============================================
# 2. Script workflow (normally do not modify)
# ============================================

# Set up SSH SOCKS5 proxy
if /usr/bin/pgrep -f "ssh -fN -D 127.0.0.1:${PROXY_PORT}" >/dev/null; then
    echo "ok [SSH proxy port 127.0.0.1:${PROXY_PORT} already running]"
else
    if /usr/bin/ssh -fN -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}; then
        echo "ok [SSH proxy started on 127.0.0.1:${PROXY_PORT} forwarding to ${VPN_MACHINE_IP}]"
    else
        echo "fail [SSH proxy started on 127.0.0.1:${PROXY_PORT} forwarding to ${VPN_MACHINE_IP}]"
    fi
fi

# Create a Chrome bookmarks file in the temporary profile
TMP_PROFILE=$(mktemp -d)
mkdir -p "${TMP_PROFILE}/Default"
if cat > "${TMP_PROFILE}/Default/Bookmarks" <<EOF
{
  "checksum": "dummy",
  "roots": {
    "bookmark_bar": {
      "children": [
        {
          "type": "url",
          "name": "vSphere Console",
          "url": "https://vcenter.cee.ibmc.devcluster.openshift.com",
          "date_added": "17625387360000000"
        },
        {
          "type": "url",
          "name": "OpenShift Console",
          "url": "https://console-openshift-console.${INGRESS_DOMAIN}/dashboards",
          "date_added": "17625390150000000"
        }
      ],
      "name": "Bookmarks Bar",
      "type": "folder"
    },
    "other": { "children": [], "name": "Other bookmarks", "type": "folder" },
    "synced": { "children": [], "name": "Mobile bookmarks", "type": "folder" }
  },
  "version": 1
}
EOF
then
    echo "ok [Create a Chrome bookmarks file in the temporary profile]"
else
    echo "fail [Create a Chrome bookmarks file in the temporary profile]"
fi

# Launch Chrome (temporary profile + new window)
echo "ok [Chrome launched with SOCKS5 proxy 127.0.0.1:${PROXY_PORT}]"
"${CHROME_APP}" --proxy-server="socks5://127.0.0.1:${PROXY_PORT}" \
  --user-data-dir="${TMP_PROFILE}" \
  --disable-features=DarkMode,WebUIDarkMode \
  --no-first-run --no-default-browser-check > /dev/null 2>&1

# Clean up temporary Chrome profile
rm -rf "${TMP_PROFILE}"
