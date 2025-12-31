#!/bin/bash
# Run this script on a Mac to access the OpenShift Console via a SOCKS5 proxy
# set -euo pipefail

# ============================================
# 1. Set environment variables
# ============================================

# Ingress domain for Chrome OCP console bookmarks
INGRESS_DOMAIN="apps.ocp.example.com"

# All domains to be accessed must be listed in the /etc/hosts file on the VPN_MACHINE_IP machine.
# VPN machine SSH access (ensure key-based authentication is set up)
# [ -f ~/.ssh/id_rsa ] || ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa && ssh-copy-id $VPN_MACHINE_USER@$VPN_MACHINE_IP
VPN_MACHINE_IP="10.0.79.55"
VPN_MACHINE_USER="root"

# Proxy port for local PC (change only if conflicts occur)
PROXY_PORT="8888"

# Chrome executable path (default for macOS; modify if installed elsewhere)
PROFILE_DIR="$HOME/.chrome-ocp-profile"
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# ============================================
# 2. Script workflow (normally do not modify)
# ============================================

# Check if SSH SOCKS5 proxy is running on the specified port; start it if not
if /usr/bin/pgrep -f "ssh -fN -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}" >/dev/null; then
    : #printf "\e[96mINFO\e[0m SSH proxy port 127.0.0.1:${PROXY_PORT} already running\n"
else
    if /usr/bin/ssh -fN -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP} >/dev/null 2>&1; then
        : #printf "\e[96mINFO\e[0m SSH proxy started on 127.0.0.1:${PROXY_PORT} forwarding to ${VPN_MACHINE_IP}\n"
    else
        printf "\e[31mFAILED\e[0m SSH proxy started on 127.0.0.1:${PROXY_PORT} forwarding to ${VPN_MACHINE_IP}\n"
        exit 1
    fi
fi

# Create the Default directory inside the profile
if [ ! -d "${PROFILE_DIR}" ]; then
    if mkdir -p "${PROFILE_DIR}/Default" 2>/dev/null; then
        : #printf "\e[96mINFO\e[0m Chrome profile directory created: ${PROFILE_DIR}\n"
    else
        printf "\e[31mFAILED\e[0m Chrome profile directory created: ${PROFILE_DIR}\n"
        exit 1
    fi
fi

# Write Chrome bookmarks to the profile
if cat > "${PROFILE_DIR}/Default/Bookmarks" <<EOF
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
    : #printf "\e[96mINFO\e[0m Create a Chrome bookmarks file in the profile\n"
else
    printf "\e[31mFAILED\e[0m Create a Chrome bookmarks file in the profile\n"
    exit 1
fi

# Launch Chrome with the profile and SOCKS5 proxy
"$CHROME_APP" --proxy-server="socks5://127.0.0.1:${PROXY_PORT}" \
    --user-data-dir="${PROFILE_DIR}" \
    --disable-features=DarkMode,WebUIDarkMode \
    --disable-background-networking \
    --disable-component-update \
    --disable-sync \
    --no-first-run \
    --no-default-browser-check \
    > /dev/null 2>&1 &

CHROME_PID=$!

# Give Chrome a moment to start
sleep 1

# Check if Chrome started successfully
if ps -p "$CHROME_PID" > /dev/null; then
    #printf "\e[96mINFO\e[0m Add required domains to /etc/hosts on $VPN_MACHINE_IP\n"
    printf "\e[96mINFO\e[0m Establishing SOCKS5 proxy to internal network\n"
else
    printf "\e[31mFAILED\e[0m Establishing SOCKS5 proxy to internal network\n"
    exit 1
fi

# Wait for Chrome parent process to exit before cleaning up (child GUI may still run)
wait $CHROME_PID
