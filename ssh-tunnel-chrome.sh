#!/bin/bash
# set -euo pipefail
# Run on macOS: launch Chrome with a SOCKS5 proxy to access the OpenShift Console
# --------------------------------------------
# 1. Set environment variables
# --------------------------------------------
INGRESS_DOMAIN="apps.yaoli.example.com"
VPN_MACHINE_IP="10.0.79.55"
VPN_MACHINE_USER="root"
PROXY_PORT="9999"

# --------------------------------------------
# Option A: Access 10.184.134.0/24 via VPN machine
# Prerequisite: 
# 1. ssh-copy-id ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}
# 2. All domains to be accessed must be listed in the /etc/hosts file on the VPN_MACHINE_IP machine.
# --------------------------------------------
SSH_SOCKS_CMD=(ssh -fN -D 127.0.0.1:${PROXY_PORT} ${VPN_MACHINE_USER}@${VPN_MACHINE_IP})

# --------------------------------------------
# Option B:  Access 10.48.55.0/24 via VPN machine and TARGET_MACHINE_IP (jump host)
# Prerequisite: 
# 1. TARGET_MACHINE_IP host must have access to both 10.184.134.0/24 and 10.48.55.0/24               
# 2. ssh-copy-id ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}             
# 3. ssh-copy-id -o ProxyJump=root@${VPN_MACHINE_IP} root@${TARGET_MACHINE_IP}
# 4. All domains to be accessed must be listed in the /etc/hosts file on the TARGET_MACHINE_IP machine.
# --------------------------------------------
TARGET_MACHINE_IP="10.184.134.77"
TARGET_MACHINE_USER="root"

#SSH_SOCKS_CMD=(
  ssh -4 -N -D ${PROXY_PORT}
  -o StrictHostKeyChecking=no
  -o ServerAliveInterval=15
  -o ServerAliveCountMax=3
  -o ExitOnForwardFailure=yes
  -o TCPKeepAlive=yes
  -J ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}
  ${TARGET_MACHINE_USER}@${TARGET_MACHINE_IP}
)

# --------------------------------------------
# 3. SSH tunnel maintenance function Ensures SOCKS5 proxy stays active (normally do not modify)
# --------------------------------------------

# Pattern used to detect running SSH process for cleanup/maintenance
CMD_STR="${SSH_SOCKS_CMD[*]}"
MATCH_PATTERN="ssh.*-D.*${PROXY_PORT}.*${TARGET_MACHINE_IP:-$VPN_MACHINE_IP}"
MAX_SSH_RETRIES=5

# SSH tunnel maintenance function Ensures SOCKS5 proxy stays active
maintain_ssh() {
    local is_first_run=$1
    while true; do
        if ! pgrep -f "$MATCH_PATTERN" >/dev/null; then
            # Start SSH tunnel
            "${SSH_SOCKS_CMD[@]}" >/dev/null 2>&1 &
            
            # Validate tunnel
            local count=0
            local success=false
            while [ $count -lt $MAX_SSH_RETRIES ]; do
                sleep 1
                if pgrep -f "$MATCH_PATTERN" >/dev/null && lsof -i tcp:${PROXY_PORT} >/dev/null 2>&1; then
                    success=true
                    break
                fi
                ((count++))
            done
            
            # Exit if this was the initial check
            if [ "$success" = false ]; then
                # printf "\e[31mFAIL\e[0m SSH tunnel could not be established on port ${PROXY_PORT}\n"
                SSH_ERROR_OUTPUT=$("${SSH_SOCKS_CMD[@]}" 2>&1 | head -n 1)
                printf "\e[31mFAIL\e[0m SSH tunnel on port ${PROXY_PORT} failed: %s\n" "$SSH_ERROR_OUTPUT"
                pgrep -f "$MATCH_PATTERN" | xargs kill -9 2>/dev/null
                exit 1
            fi
        fi
        
        # If this was the first successful run, exit the function so the script continues to Chrome
        if [ "$is_first_run" = true ]; then
            return 0
        fi
        
        sleep 5
    done
}

# First run: wait until SSH tunnel is established
maintain_ssh true

# Start SSH maintenance in background
maintain_ssh false & 
MAINTAINER_PID=$!

# To prevent the terminal from displaying "Terminated: 15"
disown $MAINTAINER_PID 2>/dev/null

# Cleanup on exit: kill SSH tunnel and maintenance process
trap '
    exec 2>/dev/null
    printf "\r\033[K"
    if [ -n "$MAINTAINER_PID" ]; then
        kill $MAINTAINER_PID 2>/dev/null
    fi
    # Kill the actual SSH process matching our port
    pgrep -f "$MATCH_PATTERN" | xargs kill -9 2>/dev/null
    # printf "\e[96mINFO\e[0m Proxy SSH processes stopped and exiting\n"
    exit
' EXIT

# --------------------------------------------
# 4. Chrome profile and bookmarks
# --------------------------------------------

# Create bookmarks for vSphere and OpenShift console
# Chrome executable path (default for macOS; modify if installed elsewhere)
PROFILE_DIR="$HOME/.chrome-ocp-profile"
CHROME_APP="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"


# Create the Chrome Default directory inside the profile
if [ ! -d "${PROFILE_DIR}" ]; then
    if mkdir -p "${PROFILE_DIR}/Default" 2>/dev/null; then
        : #printf "\e[96mINFO\e[0m Chrome profile directory created: ${PROFILE_DIR}\n"
    else
        printf "\e[31mFAIL\e[0m Chrome profile directory created: ${PROFILE_DIR}\n"
        exit 1
    fi
fi

# Create bookmarks for vSphere and OpenShift console
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
    printf "\e[31mFAIL\e[0m Create a Chrome bookmarks file in the profile\n"
    exit 1
fi

# --------------------------------------------
# 5. Launch Chrome with SOCKS5 proxy
# --------------------------------------------

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

# Check Chrome launch
if ps -p "$CHROME_PID" > /dev/null; then
    #printf "\e[96mINFO\e[0m Add required domains to /etc/hosts on $VPN_MACHINE_IP\n"
    printf "\e[96mINFO\e[0m Establishing SOCKS5 proxy to internal network\n"
    
else
    printf "\e[31mFAIL\e[0m Establishing SOCKS5 proxy to internal network\n"
    exit 1
fi

# Wait until Chrome exits to clean up
wait $CHROME_PID
