#!/bin/bash
# set -euo pipefail
# Run on macOS: Launch Chrome through a SOCKS5 proxy to access the internal network

# --------------------------------------------
# 1. Set environment variables
# --------------------------------------------
# Mandatory:  Access 10.184.134.0/24 via VPN machine
# Prerequisite: 
# - ssh-copy-id ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}
# - Domain name resolution relies on /etc/hosts entries on the VPN machine
# --------------------------------------------
INGRESS_DOMAIN="apps.copan.ocp.test"
VPN_MACHINE_IP="10.0.79.55"     # 10.72.94.215
VPN_MACHINE_USER="root"
PROXY_PORT="9999"

# --------------------------------------------
# Optional:  Access 10.48.55.0/24 via VPN machine and TARGET_MACHINE_IP
# Prerequisite: 
# - TARGET_MACHINE_IP host must have access to both 10.184.134.0/24 and 10.48.55.0/24               
# - ssh-copy-id ${VPN_MACHINE_USER}@${VPN_MACHINE_IP}
# - ssh-copy-id -o ProxyJump=${VPN_MACHINE_USER}@${VPN_MACHINE_IP} ${TARGET_MACHINE_USER}@${TARGET_MACHINE_IP}
# - Domain name resolution relies on the /etc/hosts entries or DNS on the TARGET_MACHINE_IP
# --------------------------------------------
#TARGET_MACHINE_IP="10.184.134.30"
#TARGET_MACHINE_USER="root"

# --------------------------------------------
# 2. SSH options (persistent and stable)
# --------------------------------------------
# Define common SSH options for stability and persistence
SSH_COMMON_OPTS=(
    -C -f -N  
    -D "127.0.0.1:${PROXY_PORT}" 
    -o ServerAliveInterval=15 
    -o ServerAliveCountMax=3 
    -o ExitOnForwardFailure=yes 
    -o TCPKeepAlive=yes
    -o StrictHostKeyChecking=no
)

# --------------------------------------------
# 3. Determine SSH command and matching pattern
# --------------------------------------------
# Core Logic: Determine connection mode based on TARGET_MACHINE_IP
if [ -n "$TARGET_MACHINE_IP" ]; then
    # Triggered if TARGET_MACHINE_IP is defined; routes through VPN_MACHINE
    # printf "\e[96mINFO\e[0m Jump Host via ${VPN_MACHINE_IP} to ${TARGET_MACHINE_IP}\n"    
    SSH_SOCKS_CMD=(
        ssh "${SSH_COMMON_OPTS[@]}" -J "${VPN_MACHINE_USER}@${VPN_MACHINE_IP}" "${TARGET_MACHINE_USER}@${TARGET_MACHINE_IP}"
    )
    # Target for process matching
    MATCH_PATTERN="ssh.*-D 127.0.0.1:${PROXY_PORT}.*${TARGET_MACHINE_IP}"
else
    # Triggered if TARGET_MACHINE_IP is empty; connects directly to VPN_MACHINE
    # printf "\e[96mINFO\e[0m Direct Connection to ${VPN_MACHINE_IP}\n"
    SSH_SOCKS_CMD=(
        ssh "${SSH_COMMON_OPTS[@]}" "${VPN_MACHINE_USER}@${VPN_MACHINE_IP}"
    )
    # Target for process matching
    MATCH_PATTERN="ssh.*-D 127.0.0.1:${PROXY_PORT}.*${VPN_MACHINE_IP}"
fi

# --------------------------------------------
# 4. SSH tunnel maintenance function
# --------------------------------------------
# SSH tunnel maintenance function: Ensures SOCKS5 proxy stays active and matches configuration
MAX_SSH_RETRIES=200
maintain_ssh() {
    local is_first_run=$1
    while true; do
        # 1. Check and terminate existing processes that don't match the current mode
        for pid in $(lsof -ti tcp:${PROXY_PORT}); do
            cmd_line=$(ps -p "$pid" -o command=)
            
            # Logic: (Jump required but process lacks -J or target IP) OR (Direct required but process has -J or wrong VPN IP)
            if [[ -n "$TARGET_MACHINE_IP" && ("$cmd_line" != *"-J"* || "$cmd_line" != *"$TARGET_MACHINE_IP"*) ]] || \
               [[ -z "$TARGET_MACHINE_IP" && ("$cmd_line" == *"-J"* || "$cmd_line" != *"$VPN_MACHINE_IP"*) ]]; then
                kill -9 "$pid" 2>/dev/null && sleep 0.5
            fi
        done
        
        # 2. Check if a valid tunnel matching our pattern is already running
        if ! pgrep -f "$MATCH_PATTERN" >/dev/null; then
            # Launch SSH
            "${SSH_SOCKS_CMD[@]}" >/dev/null 2>&1 &

            # 3. Wait for the port to become active (max 20 seconds)
            local count=0
            local success=false
            while [ $count -lt $MAX_SSH_RETRIES ]; do
                # Verify both the process exists and the port is listening
                if pgrep -f "$MATCH_PATTERN" >/dev/null && lsof -i tcp:${PROXY_PORT} >/dev/null 2>&1; then
                    success=true
                    break
                fi
                sleep 0.1
                ((count++))
            done

            # If the tunnel fails to establish within the retry limit
            if [ "$success" = false ]; then
                # Capture the first line of the actual SSH error for debugging
                local err=$("${SSH_SOCKS_CMD[@]}" 2>&1 | head -n1)
                printf "\e[31mFAIL\e[0m SSH tunnel on port ${PROXY_PORT} failed: %s\n" "$err"
                # Cleanup any partial or zombie processes
                pgrep -f "$MATCH_PATTERN" | xargs kill -9 2>/dev/null
                exit 1
            fi
        fi

        # Exit after first successful run for main script continuation
        if [ "$is_first_run" = true ]; then
            return 0
        fi
        # Monitor every 5 seconds in the background
        sleep 5
    done
}

# --------------------------------------------
# 5. Start SSH tunnel
# --------------------------------------------
# First run: wait until SSH tunnel is established
maintain_ssh true

# Start SSH maintenance in background
maintain_ssh false & 
MAINTAINER_PID=$!

# To prevent the terminal from displaying "Terminated: 15"
disown $MAINTAINER_PID 2>/dev/null

# --------------------------------------------
# 6. Cleanup on exit
# --------------------------------------------
# Cleanup on exit: kill SSH tunnel and maintenance process
trap '
    exec 2>/dev/null
    printf "\r\033[K"
    if [ -n "$MAINTAINER_PID" ]; then
        kill $MAINTAINER_PID 2>/dev/null
    fi
    # Kill the actual SSH process matching our port
    pgrep -f "ssh .* -D 127.0.0.1:${PROXY_PORT}" | xargs kill -9 2>/dev/null
    # printf "\e[96mINFO\e[0m Proxy SSH processes stopped and exiting\n"
    exit
' EXIT

# --------------------------------------------
# 7. Configure Google Chrome profile and bookmarks
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
          "name": "OCP Console",
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
# 8. Launch Google Chrome using the SOCKS5 proxy
# --------------------------------------------
# Close existing Chrome instances using the same profile
pkill -f "Google Chrome.*--user-data-dir=${PROFILE_DIR}" 2>/dev/null

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

# --------------------------------------------
# 9. Verify Chrome launch and SOCKS5 proxy
# --------------------------------------------
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
