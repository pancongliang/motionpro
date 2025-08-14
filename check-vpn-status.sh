#!/bin/bash

# Define log file path
LOG_FILE="/var/log/motionpro.log"

# Get VPN status
VPN_STATUS=$(/usr/bin/podman exec -it VPNcontainer /opt/MotionPro/vpn_cmdline --status)

# Current time
CURRENT_TIME=$(date "+%Y-%m-%d %H:%M:%S")

# Check if VPN status is "connected"
if [[ "$VPN_STATUS" != *"connected"* ]]; then
    # Log: VPN not connected.
    echo "$CURRENT_TIME - MotionPro VPN not connected" >> $LOG_FILE
    
    # Restart the VPNcontainer service
    systemctl restart VPNcontainer.service
    
    # Log: VPNcontainer service has been restarted
    echo "$CURRENT_TIME - MotionPro VPNcontainer service restarted" >> $LOG_FILE
else
    # Log: VPN is connected
    echo "$CURRENT_TIME - MotionPro VPN is connected" >> $LOG_FILE
fi
