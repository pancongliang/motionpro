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

# Proxy port for local PC (change only if conflicts occur)
PROXY_PORT="8899"

# Chrome executable path (default for macOS; modify if installed elsewhere)
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


# ============================================
# 2. Script workflow (normally do not modify)
# ============================================

# Check if SSH SOCKS5 proxy is running on the specified port; start it if not
if /usr/bin/pgrep -f "ssh .* -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}" >/dev/null; then
    : #echo "ok [SSH proxy port 127.0.0.1:${PROXY_PORT} already running]"
else
    if /usr/bin/ssh -o ConnectTimeout=10 -fN -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP} >/dev/null 2>&1; then
        : #echo "ok [SSH proxy started on 127.0.0.1:${PROXY_PORT} forwarding to ${VPN_MACHINE_IP}]"
    else
        echo "fail [SSH proxy started on 127.0.0.1:${PROXY_PORT} forwarding to ${VPN_MACHINE_IP}]"
        exit 1
    fi
fi

# Create a temporary Chrome profile directory
if TMP_PROFILE=$(mktemp -d); then
    : #echo "ok [Create temporary Chrome profile directory]"
else
    echo "fail [Create temporary Chrome profile directory]"
    exit 1
fi

# Register a cleanup trap to remove the temporary profile after Chrome exits
trap '
if ps -p $CHROME_PID > /dev/null 2>&1; then
    wait $CHROME_PID 2>/dev/null
fi
rm -rf $TMP_PROFILE > /dev/null 2>&1 || true
' EXIT

# Create the Default directory inside the temporary profile
if mkdir -p "${TMP_PROFILE}/Default" >/dev/null 2>&1; then
    : #echo "ok [Ceate Default directory in ${TMP_PROFILE}]"
else
    echo "fail [Ceate Default directory in ${TMP_PROFILE}]"
    exit 1
fi

# Write Chrome bookmarks to the temporary profile
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
    : #echo "ok [Create a Chrome bookmarks file in the temporary profile]"
else
    echo "fail [Create a Chrome bookmarks file in the temporary profile]"
    exit 1
fi

# Launch Chrome with the temporary profile and SOCKS5 proxy
"$CHROME_APP" --proxy-server="socks5://127.0.0.1:${PROXY_PORT}" \
    --user-data-dir="${TMP_PROFILE}" \
    --disable-features=DarkMode,WebUIDarkMode \
    --no-first-run --no-default-browser-check \
    > /dev/null 2>&1 &

CHROME_PID=$!

# Give Chrome a moment to start
sleep 0.5

# Check if Chrome started successfully
if ps -p $CHROME_PID > /dev/null; then
    echo "ok [Establishing SOCKS5 proxy to internal network]"
else
    echo "fail [Establishing SOCKS5 proxy to internal network]"
    exit 1
fi

# Wait for Chrome parent process to exit before cleaning up (child GUI may still run)
wait $CHROME_PID
