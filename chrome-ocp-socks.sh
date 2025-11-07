#!/bin/bash
set -euo pipefail

# Basic Configuration
VPN_MACHINE_IP="10.0.79.55"
VPN_MACHINE_USER="root"
PROXY_PORT="8899"

# Usually no need to change
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP_PROFILE=$(mktemp -d)

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

# Launch Chrome (temporary profile + new window)
echo "ok [Chrome launched with SOCKS5 proxy 127.0.0.1:${PROXY_PORT}]"
"${CHROME_APP}" --proxy-server="socks5://127.0.0.1:${PROXY_PORT}" \
  --user-data-dir="${TMP_PROFILE}" \
  --disable-features=DarkMode,WebUIDarkMode \
  --no-first-run --no-default-browser-check > /dev/null 2>&1
# --new-window "${URL}" # URL="https://console-openshift-console.apps.ocp.example.com"

# Clean up temporary Chrome profile
if rm -rf "${TMP_PROFILE}"; then
    echo "ok [Clean up temporary Chrome profile]"
else
    echo "fail [Clean up temporary Chrome profile]"
fi
