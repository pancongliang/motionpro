#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -euo pipefail
trap 'echo -e "\e[31mFAILED\e[0m Line $LINENO - Command: $BASH_COMMAND"; exit 1' ERR

# Run the script as root user
# VPN Information
export USER='xxxxxx'
export PASSWD='xxxxxx'
export METHOD=radius

# VPN Host Information 
export NETWORK_CIDR="10.72.94.0/24"
export GATEWAY="10.72.94.254"
export INTERFACE="ens192"
export DNS="10.72.17.5"


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
    local exit_code=$?
    if [ $exit_code -eq 0 ]; then
        echo -e "\e[96mINFO\e[0m $1"
    else
        echo -e "\e[31mFAILED\e[0m $1"
        exit 1
    fi
}

PRINT_TASK "TASK [Install and Configure MotionPro VPN]"

# Stop and disable firewalld services
if sudo systemctl list-unit-files firewalld.service >/dev/null 2>&1; then
    sudo systemctl disable --now firewalld >/dev/null 2>&1
    run_command "Stop and disable firewalld service"
fi

# Read the SELinux configuration
permanent_status=$(sudo grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo -e "\e[96mINFO\e[0m Set permanent selinux policy to $permanent_status"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo -e "\e[96mINFO\e[0m Permanent selinux policy is already $permanent_status"

else
    echo -e "\e[31mFAILED\e[0m SELinux permanent policy is $permanent_status, expected permissive or disabled"
fi

# Temporarily set SELinux security policy to permissive
sudo setenforce 0 >/dev/null 2>&1 || true
run_command "Disable temporary selinux enforcement"

if [ -f /opt/MotionPro/vpn_cmdline ]; then
    run_command "Deleting existing MotionPro..."
    sudo bash -c "nohup /opt/MotionPro/install.sh -u >/dev/null 2>&1 </dev/null &"
fi

sudo rm -rf MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1 || true
sudo rm -rf /opt/MotionPro/ >/dev/null 2>&1 || true

sudo ip route add $DNS via $GATEWAY dev $INTERFACE >/dev/null 2>&1 || true
sudo ip rule add from $NETWORK_CIDR table 100 >/dev/null 2>&1 || true
sudo ip route add default via $GATEWAY dev $INTERFACE table 100 >/dev/null 2>&1 || true
run_command "Add temporary routing rules"

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
run_command "Add persistent routing rules"

sudo chmod +x /etc/rc.d/rc.local >/dev/null 2>&1
run_command "Set permissions for /etc/rc.d/rc.local"

echo -e "\e[96mINFO\e[0m Downloading MotionPro software package"

sudo curl -OL https://support.arraynetworks.net/prx/000/http/supportportal.arraynetworks.net/downloads/pkg_9_4_5_8/MP_Linux_1.2.18/MotionPro_Linux_RedHat_x64_build-8383-30.sh &> /dev/null
run_command "Download MotionPro software package"

sudo chmod +x MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1
run_command "Set permissions for MotionPro_Linux_RedHat_x64_build-8383-30.sh"

echo -e "\e[96mINFO\e[0m Installing MotionPro VPN"

sudo sh MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1
run_command "Installation complete"

sudo rm -rf MotionPro_Linux_RedHat_x64_build-8383-30.sh >/dev/null 2>&1 || true

echo -e "\e[96mINFO\e[0m Finding the VPN host with the lowest latency"

# Test to find the VPN site with the lowest latency
hosts=(
"vpn.dal.softlayer.com"
"vpn.mon01.softlayer.com"
"vpn.sjc.softlayer.com"
"vpn.tor.softlayer.com"
"vpn.wdc.softlayer.com"
"vpn.sao.softlayer.com"
"vpn.ams03.softlayer.com"
"vpn.fra.softlayer.com"
"vpn.lon.softlayer.com"
"vpn.mil01.softlayer.com"
"vpn.par.softlayer.com"
"vpn.par01.softlayer.com"
"vpn.che01.softlayer.com"
"vpn.osa.softlayer.com"
"vpn.sng01.softlayer.com"
"vpn.syd.softlayer.com"
"vpn.tok.softlayer.com"
)

min_latency=999999
HOST=""

for host in "${hosts[@]}"; do
    # Get avg latency (3 pings, 2s timeout)
    latency_raw=$(ping -c 3 -W 2 "$host" 2>/dev/null | tail -1 | awk -F '/' '{print $5}')
    
    if [ -n "$latency_raw" ]; then
        # Compare as integers (strip dots)
        latency_int=$(echo "$latency_raw" | tr -d '.')
        
        if [ "$latency_int" -lt "$min_latency" ]; then
            min_latency=$latency_int
            HOST=$host
        fi
    fi
done

# Save the best node as a variable
echo -e "\e[96mINFO\e[0m Apply the best VPN host: $HOST"

sudo rm -rf /var/log/motionpro.log >/dev/null 2>&1 || true
sudo touch /var/log/motionpro.log >/dev/null 2>&1
run_command "Create /var/log/motionpro.log file"

sudo chmod 777 /var/log/motionpro.log >/dev/null 2>&1
run_command "Set permissions for /var/log/motionpro.log"

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
run_command "Create motionpro-auto-reconnect.sh script"

sudo chmod +x /opt/MotionPro/motionpro-auto-reconnect.sh &> /dev/null
run_command "Set permissions for /opt/MotionPro/motionpro-auto-reconnect.sh"

sudo echo "*/1 * * * * /opt/MotionPro/motionpro-auto-reconnect.sh" | crontab -
run_command "Add crontab to check MotionPro status"

rm -rf /tmp/mycron >/dev/null 2>&1 || true

sudo rm -rf /etc/profile.d/aliases.sh
cat << 'EOF' > /etc/profile.d/aliases.sh
alias vpn='bash /opt/MotionPro/motionpro-auto-reconnect.sh'
EOF

# Add an empty line after the task
echo

PRINT_TASK "[TASK: Install the GNOME Desktop]"

echo "info: Gnome desktop installation is underway..."

sudo dnf groupinstall workstation -y &> /dev/null
run_command "Gnome desktop has been installed"

sudo systemctl set-default graphical.target &> /dev/null
run_command "Sets the default system boot target to graphical mode"

sudo systemctl isolate graphical.target &> /dev/null
run_command "Immediately switches the current session to graphical mode without rebooting"

sudo systemctl disable firewalld >/dev/null 2>&1 || true
sudo systemctl stop firewalld >/dev/null 2>&1 || true

# Add an empty line after the task
echo

PRINT_TASK "[TASK: Install and configure chrome]"

sudo dnf remove google-chrome-stable_current_x86_64.rpm &> /dev/null
rm -rf google-chrome-stable_current_x86_64.rpm &> /dev/null
sudo curl -OL https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm &> /dev/null
run_command "Download google chrome rpm"

sudo dnf install -y google-chrome-stable_current_x86_64.rpm &> /dev/null
run_command "Install google chrome rpm"

sudo sed -i 's|exec -a "$0" "$HERE/chrome" "$@"|exec -a "$0" "$HERE/chrome" "$@" --user-data-dir --test-type --no-sandbox|' /opt/google/chrome/google-chrome
run_command "Changing to root user can also use chrome"

rm -rf google-chrome-stable_current_x86_64.rpm &> /dev/null

# Add an empty line after the task
echo

PRINT_TASK "[TASK: Install and configure RDP]"

sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm &> /dev/null
run_command "Modify install epel-release-latest-9.noarch"

sudo dnf install xrdp tigervnc-server -y &> /dev/null
run_command "Install xrdp and tigervnc-server rpm"

sudo systemctl enable xrdp --now &> /dev/null
run_command "Enable and restart xrdp.service"

sudo rm -rf /etc/xrdp/startwm.sh
sudo cat <<EOF > /etc/xrdp/startwm.sh
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec /usr/bin/gnome-session
EOF
run_command "Create the /etc/xrdp/startwm.sh file"

sudo systemctl restart xrdp &> /dev/null
run_command "Restart xrdp.service"

# Add an empty line after the task
echo

PRINT_TASK "[TASK: Post-installation Configuration]"
echo -e "\e[33mNOTE\e[0m Reboot the machine to apply any changes"
echo -e "\e[33mNOTE\e[0m Install Windows Applications for Remote Desktop from the Mac App Store"
echo -e "\e[33mNOTE\e[0m To access the VPN network via web, run 'ssh-tunnel-chrome.sh' on your PC"
echo -e "\e[33mNOTE\e[0m Auto check/reconnect VPN every minute; Can also manually restart using 'vpn'"
