#!/bin/bash
# Enable strict mode for robust error handling and log failures with line number.
set -u

# VPN Information
export USER='xxxx@xxx.com'
export PASSWD='xxxx'
export HOST='vpn.wdc.softlayer.com'
export METHOD=radius

# VPN Host Information 
export NETWORK="10.0.78.0/23"
export GATEWAY="10.0.79.254"
export INTERFACE="eth0"
export DNS="10.11.5.160"
export DEST_NETWORK="10.72.94.0/24"  # Options: Additional networks to access, if none leave it as default

# Function to print a task with uniform length
PRINT_TASK() {
    max_length=110  # Adjust this to your desired maximum length
    task_title="$1"
    title_length=${#task_title}
    stars=$((max_length - title_length))

    echo "$task_title$(printf '*%.0s' $(seq 1 $stars))"
}
# ====================================================

# Function to check command success and display appropriate message
run_command() {
    if [ $? -eq 0 ]; then
        echo "ok: $1"
    else
        echo "failed: $1"
    fi
}
# === Task: Disable and stop firewalld service ===
PRINT_TASK "[TASK: Disable and stop firewalld service]"

# Stop and disable firewalld services
sudo systemctl disable --now firewalld >/dev/null 2>&1 || true
sudo systemctl stop firewalld >/dev/null 2>&1 || true
run_command "[firewalld service stopped and disabled]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Change SELinux security policy ===
PRINT_TASK "[TASK: Change SELinux security policy]"

# Read the SELinux configuration
permanent_status=$(grep "^SELINUX=" /etc/selinux/config | cut -d= -f2)
# Check if the permanent status is Enforcing
if [[ $permanent_status == "enforcing" ]]; then
    # Change SELinux to permissive
    sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config
    permanent_status="permissive"
    echo "ok: [selinux permanent security policy changed to $permanent_status]"
elif [[ $permanent_status =~ ^[Dd]isabled$ ]] || [[ $permanent_status == "permissive" ]]; then
    echo "ok: [selinux permanent security policy is $permanent_status]"
else
    echo "failed: [selinux permanent security policy is $permanent_status (expected permissive or disabled)]"
fi

# Temporarily set SELinux security policy to permissive
sudo setenforce 0 &>/dev/null
# Check temporary SELinux security policy
temporary_status=$(getenforce)
# Check if temporary SELinux security policy is permissive or disabled
if [[ $temporary_status == "Permissive" || $temporary_status == "Disabled" ]]; then
    echo "ok: [selinux temporary security policy is disabled]"
else
    echo "failed: [selinux temporary security policy is $temporary_status (expected permissive or disabled)]"
fi

# Add an empty line after the task
echo
# ====================================================


# === Task: Install and configure MotionPro ===
PRINT_TASK "[TASK: Install and configure MotionPro]"

sudo /opt/MotionPro/install.sh -u >/dev/null 2>&1 || true
rm -rf MotionPro_Linux_RedHat_x64_build-8383-30.sh

ip route add $DNS via $GATEWAY dev $INTERFACE
ip rule add from $NETWORK table 100
ip route add default via $GATEWAY dev $INTERFACE table 100
ip route add $DEST_NETWORK via $GATEWAY dev $INTERFACE
run_command "[adding a temporary routing rules]"

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
ip rule add from $NETWORK table 100
ip route add default via $GATEWAY dev $INTERFACE table 100
ip route add $DEST_NETWORK via $GATEWAY dev $INTERFACE
EOF
run_command "[adding persistent routing rules]"

sudo chmod +x /etc/rc.d/rc.local &> /dev/null
run_command "[modify /etc/rc.d/rc.local permissions]"

sudo curl -OL https://support.arraynetworks.net/prx/000/http/supportportal.arraynetworks.net/downloads/pkg_9_4_5_8/MP_Linux_1.2.18/MotionPro_Linux_RedHat_x64_build-8383-30.sh &> /dev/null
run_command "[download motionpro vpn]"

sudo chmod +x MotionPro_Linux_RedHat_x64_build-8383-30.sh &> /dev/null
run_command "[modify MotionPro_Linux_RedHat_x64_build-8383-30.sh permissions]"

sudo sh MotionPro_Linux_RedHat_x64_build-8383-30.sh &> /dev/null
run_command "[install motionpro vpn]"


MOTIONPRO_LOG="/var/log/motionpro.log"
sudo rm -rf $MOTIONPRO_LOG >/dev/null 2>&1 || true

sudo touch $MOTIONPRO_LOG 
run_command "[create $MOTIONPRO_LOG]"

sudo chmod 777 $MOTIONPRO_LOG
run_command "[modify $MOTIONPRO_LOG file permissions]"

sudo rm -rf /opt/MotionPro/check-motionpro-status.sh >/dev/null 2>&1 || true
sudo cat <<EOF > /opt/MotionPro/check-motionpro-status.sh
# Define log file path
LOG_FILE="$MOTIONPRO_LOG"

# Get VPN status
VPN_STATUS=\$(/opt/MotionPro/vpn_cmdline --status)

# Current time
CURRENT_TIME=\$(date "+%Y-%m-%d %H:%M:%S")
a
# Check if VPN status is "connected"
if [[ "\$VPN_STATUS" != *"connected"* ]]; then
    # Log: VPN not connected.
    echo "\$CURRENT_TIME - MotionPro VPN not connected" >> \$LOG_FILE
    
    # Restart the VPNcontainer service
    sudo /opt/MotionPro/vpn_cmdline --method $METHOD -h $HOST -u $USER -p $PASSWD -c inf --loglevel warn
    
    # Log: VPNcontainer service has been restarted
    echo "\$CURRENT_TIME - MotionPro VPN service restarted" >> \$LOG_FILE
else
    # Log: VPN is connected
    echo "\$CURRENT_TIME - MotionPro VPN is connected" >> \$LOG_FILE
fi
EOF
run_command "[create the check-motionpro-status.sh script]"

sudo chmod +x /opt/MotionPro/check-motionpro-status.sh &> /dev/null
run_command "[modify /opt/MotionPro/check-motionpro-status.sh permissions]"

#sudo crontab -l > /tmp/mycron
#sudo echo "*/2 * * * * /opt/MotionPro/check-motionpro-status.sh" >> crontab -l/tmp/mycron
#sudo crontab /tmp/mycron
sudo echo "*/3 * * * * /opt/MotionPro/check-motionpro-status.sh" | crontab -
run_command "[Add a crontab to check the motionpro status]"
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
run_command "[create the motionpro.service systemd]"

sudo systemctl daemon-reload &> /dev/null
run_command "[systemctl daemon-reload]"

sudo systemctl enable MotionPro.service >/dev/null 2>&1 || true
run_command "[enable motionpro.service]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Install and configure chrome ===
PRINT_TASK "[TASK: Install and configure chrome]"

sudo dnf remove google-chrome-stable_current_x86_64.rpm &> /dev/null
rm -rf google-chrome-stable_current_x86_64.rpm &> /dev/null
sudo curl -OL https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm &> /dev/null
run_command "[download google chrome rpm]"

sudo dnf install -y google-chrome-stable_current_x86_64.rpm &> /dev/null
run_command "[install google chrome rpm]"

sudo sed -i 's|exec -a "$0" "$HERE/chrome" "$@"|exec -a "$0" "$HERE/chrome" "$@" --user-data-dir --test-type --no-sandbox|' /opt/google/chrome/google-chrome
run_command "[changing to root user can also use chrome]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Start gnome-desktop with 200% scaling ===
#PRINT_TASK "[TASK: Start gnome-desktop with 200% scaling]"

#sudo rm -rf $HOME/.config/autostart &> /dev/null
#sudo mkdir -p $HOME/.config/autostart &> /dev/null
#sudo chmod 777 $HOME/.config/autostart &> /dev/null 
#sudo cat <<EOF > $HOME/.config/autostart/gnome-scaling.desktop
#[Desktop Entry]
#Type=Application
#Exec=/usr/bin/gsettings set org.gnome.desktop.interface scaling-factor 2
#Hidden=false
#X-GNOME-Autostart-enabled=true
#Name=GNOME Scaling
#Comment=Apply 200% scaling on startup
#EOF
#run_command "[create the $HOME/.config/autostart/gnome-scaling.desktop file]"

#sudo chmod 777 $HOME/.config/autostart/gnome-scaling.desktop &> /dev/null
#run_command "[modify $HOME/.config/autostart/gnome-scaling.desktop permissions]"

# Add an empty line after the task
#echo
# ====================================================


# === Task: Install and configure RDP  ===
PRINT_TASK "[TASK: Install and configure RDP]"

sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm &> /dev/null
run_command "[modify install epel-release-latest-9.noarch]"

#sudo dnf config-manager --set-enabled epel &> /dev/null
#run_command "[enable epel repositories]"

sudo dnf install xrdp tigervnc-server -y &> /dev/null
run_command "[install xrdp and tigervnc-server rpm]"

sudo systemctl enable xrdp --now &> /dev/null
run_command "[enable and restart xrdp.service]"

#sudo firewall-cmd --add-port=3389/tcp --permanent
#sudo firewall-cmd --reload
#sudo setsebool -P xrdp_can_connect_network 1

sudo rm -rf /etc/xrdp/startwm.sh
sudo cat <<EOF > /etc/xrdp/startwm.sh
#!/bin/bash
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR
exec /usr/bin/gnome-session
EOF
run_command "[create the /etc/xrdp/startwm.sh file]"

sudo systemctl restart xrdp &> /dev/null
run_command "[restart xrdp.service]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Install Windows App on MAC ===
PRINT_TASK "[TASK: Install Windows App on MAC]"

echo "info: [install windows apps from the mac app store]"
echo "info: [enable retina when editing remotely via windows app]"
echo "info: [when remotely connected via windows app, the resolution can be changed to the highest]"

# Add an empty line after the task
echo
# ====================================================


# === Task: Finally reboot the machine manually ===
PRINT_TASK "[finally reboot the machine manually]"

echo "warn: [finally reboot the machine manually]"
echo "warn: [finally reboot the machine manually]"
echo "warn: [Finally reboot the machine manually]"

# Add an empty line after the task
echo
# ====================================================
