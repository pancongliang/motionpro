#!/bin/bash

# Basic Configuration
VPN_MACHINE_IP="10.0.79.55"  
VPN_MACHINE_USER="root"
PROXY_PORT="8899"

# Usually no need to change
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
TMP_PROFILE=$(mktemp -d)
# URL="https://console-openshift-console.apps.ocp.example.com"

# Set up SSH SOCKS5 proxy
ssh -fN -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}

# Launch Chrome (temporary profile + new window)
"${CHROME_APP}" \
  --proxy-server="socks5://127.0.0.1:${PROXY_PORT}" \
  --user-data-dir="${TMP_PROFILE}" \
  --no-first-run --no-default-browser-check \
#  --new-window "${URL}"

# Clean up temporary profile after Chrome exits
rm -rf "${TMP_PROFILE}"
