# motion-pro-vpn-client

### 1. Install podman

~~~
yum install -y podman
~~~

### 2. Setting Environment Variables

~~~
export USER='xxxx@xxx.com'
export PASSWD='xxxx'
export HOST='vpn.tok.softlayer.com'
export METHOD=radius
~~~

### 3. Build Dockerfile

~~~
./buildit.sh
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
ssh-copy-id root@<Target machine inside VPN>
~~~

~~~
crontab -e
~~~
~~~
# Restart the container to keep the VPN token valid.
*/10 * * * * ssh -o BatchMode=yes -o ConnectTimeout=15 -t root@10.184.134.128 'date' && echo "$(date): SSH Succeeded" >> /var/log/ssh.log 2>&1 || { echo "$(date): SSH Failed" >> /var/log/ssh.log 2>&1; /bin/systemctl restart VPNcontainer.service && echo "$(date): VPNcontainer restarted" >> /var/log/ssh.log 2>&1; }
~~~

### 6. Add a route so that clients can ssh to the VPN-enabled machine
~~~
export NETWORK="10.72.94.0/24"
export GATEWAY="10.72.94.254"
export INTERFACE="ens192"

cat << EOF > 2
#!/bin/bash
ip rule add from $NETWORK table 100
ip route add default via $GATEWAY dev $INTERFACE table 100
EOF

chmod +x /etc/rc.d/rc.local
~~~

### 7. Access Target environment
~~~
ssh root@<Target machine inside VPN>
~~~
