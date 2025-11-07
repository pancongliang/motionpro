#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail

# VPN Information
export USER='xxxxx'
export PASSWD='xxxxx'
export HOST='vpn.wdc.softlayer.com'   # Run the ping-vpn.sh script and select a host with the lowest latency.< wget https://raw.githubusercontent.com/pancongliang/motion-pro-vpn-client/refs/heads/main/ping-vpn.sh >
export METHOD=radius

# VPN Host Information 
export NETWORK_CIDR="10.0.78.0/23"
export GATEWAY="10.0.79.254"
export INTERFACE="eth0"
export DNS="10.11.5.160"


# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}

PRINT_TASK "TASK [Disable Firewalld Service and Update SELinux Policy]"

# Stop and disable firewalld services
if sudo systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
    sudo systemctl disable --now firewalld >/dev/null 2>&1
    run_command "[Stop and disable firewalld service]"
fi

# Read the SELinux configuration
permanent_status=$(sudo grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo "ok: [Set permanent selinux policy to $permanent_status]"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo "ok: [Permanent selinux policy is already $permanent_status]"

else
    echo "failed: [SELinux permanent policy is $permanent_status, expected permissive or disabled]"
fi

# Temporarily set SELinux security policy to permissive
sudo setenforce 0 >/dev/null 2>&1 || true
run_command "[Disable temporary selinux enforcement]"

# Add an empty line after the task
echo

# === Task: Install and Configure MotionPro VPN ===
PRINT_TASK "TASK [Install and Configure MotionPro VPN]"

if [ -f /opt/MotionPro/vpn_cmdline ]; then
    sudo bash -c "nohup /opt/MotionPro/install.sh -u >/dev/null 2>&1 &"
    run_command "[Delete existing MotionPro]"
fi

sudo rm -rf MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1 || true
sudo rm -rf /opt/MotionPro/ >/dev/null 2>&1 || true

sudo ip route add $DNS via $GATEWAY dev $INTERFACE >/dev/null 2>&1 || true
sudo ip rule add from $NETWORK_CIDR table 100 >/dev/null 2>&1 || true
sudo ip route add default via $GATEWAY dev $INTERFACE table 100 >/dev/null 2>&1 || true
run_command "[Add temporary routing rules]"

sudo rm -rf /etc/rc.d/rc.local >/dev/null 2>&1 || true
sudo cat <<EOF > /etc/rc.d/rc.local
#!/bin/bash
# THIS FILE IS ADDED FOR COMPATIBILITY PURPOSES
#
# It is highly advisable to create own systemd services or udev rules
# to run scripts during boot instead of using this file.
#
# In contrast to previous versions due to parallel execution during boot
# this script will NOT be run after all other services.
#
# Please note that you must run 'chmod +x /etc/rc.d/rc.local' to ensure
# that this script will be executed during boot.

touch /var/lock/subsys/local

ip route add $DNS via $GATEWAY dev $INTERFACE
ip rule add from $NETWORK_CIDR table 100
ip route add default via $GATEWAY dev $INTERFACE table 100
EOF
run_command "[Add persistent routing rules]"

sudo chmod +x /etc/rc.d/rc.local >/dev/null 2>&1
run_command "[Set permissions for /etc/rc.d/rc.local]"

echo "info: [Preparing download of MotionPro VPN package]"

sudo curl -OL https://support.arraynetworks.net/prx/000/http/supportportal.arraynetworks.net/downloads/pkg_9_4_5_8/MP_Linux_1.2.18/MotionPro_Linux_RedHat_x64_build-8383-30.sh &> /dev/null
run_command "[Download MotionPro VPN]"

sudo chmod +x MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1
run_command "[Set permissions for MotionPro_Linux_RedHat_x64_build-8383-30.sh]"

sudo sh MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1
run_command "[Install MotionPro VPN]"

sudo rm -rf MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1 || true

sudo rm -rf /var/log/motionpro.log >/dev/null 2>&1 || true

sudo touch /var/log/motionpro.log >/dev/null 2>&1
run_command "[Create /var/log/motionpro.log file]"

sudo chmod 777 /var/log/motionpro.log >/dev/null 2>&1
run_command "[Set permissions for /var/log/motionpro.log]"

sudo rm -rf /opt/MotionPro/motionpro-auto-reconnect.sh >/dev/null 2>&1 || true
sudo cat <<EOF > /opt/MotionPro/motionpro-auto-reconnect.sh
#!/bin/bash

LOG_FILE="/var/log/motionpro.log"

# Log function
log() {
    local LEVEL="\$1"
    local MESSAGE="\$2"
    local CURRENT_TIME=\$(date "+%Y-%m-%d %H:%M:%S")
    echo "\$CURRENT_TIME [\$LEVEL] \$MESSAGE" >> "\$LOG_FILE"
}

# Check the vpnd daemon process
if ! pgrep -x "vpnd" >/dev/null; then
    log "WARN" "VPN daemon (vpnd) not running. Starting vpnd..."
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [WARN] VPN daemon (vpnd) not running. Starting..."
    nohup /usr/bin/vpnd >/dev/null 2>&1 &
    sleep 2
else
    log "INFO" "VPN daemon (vpnd) is already running."
fi

# Check VPN status function
check_vpn_status() {
    VPN_STATUS=\$(/opt/MotionPro/vpn_cmdline --status)
    echo "\$VPN_STATUS" | grep -q "connected"
    return \$?
}

# Start VPN function
start_vpn() {
    log "INFO" "MotionPro VPN not connected. Attempting to start..."
    /opt/MotionPro/vpn_cmdline --method $METHOD -h $HOST -u '$USER' -p '$PASSWD' -c inf --loglevel warn
}

# Main logic
if check_vpn_status; then
    log "INFO" "MotionPro VPN is already connected."
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] MotionPro VPN is already connected."
else
    log "WARN" "MotionPro VPN is not connected. Retrying..."

    for i in {1..5}; do
        log "INFO" "Attempt \$i to start VPN..."
        start_vpn
        sleep 3

        if check_vpn_status; then
            log "INFO" "VPN connected successfully on attempt \$i."
            break
        else
            log "WARN" "VPN connection failed on attempt \$i."
        fi
    done

    if check_vpn_status; then
        log "INFO" "MotionPro VPN is now connected."
    else
        log "ERROR" "Failed to connect VPN after 5 attempts."
    fi
fi
EOF
run_command "[Create motionpro-auto-reconnect.sh script]"

sudo chmod +x /opt/MotionPro/motionpro-auto-reconnect.sh &> /dev/null
run_command "[Set permissions for /opt/MotionPro/motionpro-auto-reconnect.sh]"

sudo echo "*/3 * * * * /opt/MotionPro/motionpro-auto-reconnect.sh" | crontab -
run_command "[Add crontab to check MotionPro status]"

rm -rf /tmp/mycron >/dev/null 2>&1 || true

sudo rm -rf /etc/systemd/system/MotionPro.service
cat <<EOF > /etc/systemd/system/MotionPro.service
[Unit]
Description= MotionPro
After=network.target
After=network-online.target

[Service]
Restart=always
ExecStart=/opt/MotionPro/vpn_cmdline --method $METHOD -h $HOST -u '$USER' -p '$PASSWD' -c inf --loglevel warn

[Install]
WantedBy=multi-user.target
EOF
run_command "[Create motionpro service systemd]"

sudo systemctl daemon-reload >/dev/null 2>&1
run_command "[Run systemctl daemon-reload]"

sudo systemctl enable MotionPro.service >/dev/null 2>&1
run_command "[Enable motionpro.service]"

if grep -q "alias vpn=" "$HOME/.bashrc"; then
    echo "skipped: [VPN alias already exists in $HOME/.bashrc]"
else
    echo "alias vpn='bash /opt/MotionPro/motionpro-auto-reconnect.sh'" >> "$HOME/.bashrc" 2>/dev/null
    run_command "[Add alias for 'vpn' command to $HOME/.bashrc]"
fi

echo "info: [*** Run 'source ~/.bashrc' to activate the new alias ***]"
echo "info: [*** Run the 'vpn' command to restart or check the VPN ***]"
echo "info: [*** Check VPN status every 3 minutes, auto-reconnect if disconnected ***]"

# Add an empty line after the task
echo
