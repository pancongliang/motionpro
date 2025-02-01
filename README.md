# motion-pro-vpn-client

### 1. Install podman

~~~
yum install -y podman
~~~

### 2. Build Dockerfile

~~~
./buildit.sh
~~~

### 3. Setting Environment Variables

~~~
export USER='xxxx@xxx.com'
export PASSWD='xxxx'
export HOST='pn.sng01.softlayer.com'
export METHOD=radius
~~~


### 4. Start VPNcontainer

~~~
./runit.sh 
~~~


### 5. Automatic Start VPN Container

##### Automatic Start VPN Container
~~~
cat << EOF > /etc/systemd/system/VPNcontainer.service
[Unit]
Description= VPNcontainer
After=network.target
After=network-online.target
[Service]
Restart=always
ExecStart=/usr/bin/podman start -a VPNcontainer
ExecStop=/usr/bin/podman stop -t 10 VPNcontainer
[Install]
WantedBy=multi-user.target
EOF
~~~
~~~
systemctl enable VPNcontainer.service --now
~~~

##### Restart the container to keep the VPN token valid.
~~~
cat << EOF > /$HOME/check-vpn-status.sh
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
    echo "$CURRENT_TIME - MotionPro VPN not connected." >> $LOG_FILE
    # Restart the VPNcontainer service
    systemctl restart VPNcontainer.service
    # Log: VPNcontainer service has been restarted
    echo "$CURRENT_TIME - MotionPro VPNcontainer service restarted" >> $LOG_FILE
else
    # Log: VPN is connected
    echo "$CURRENT_TIME - MotionPro VPN is connected" >> $LOG_FILE
fi
EOF
~~~

~~~
crontab -e
~~~
~~~
# Restart the container to keep the VPN token valid.
*/5 * * * * /$HOME/check-vpn-status.sh
~~~

### 6. Access Target environment
~~~
podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'
~~~
