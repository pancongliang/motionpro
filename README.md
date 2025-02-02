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

#### Automatically start VPN container when the machine starts
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

#### Restart the container to keep the VPN token valid.
~~~
crontab -e
~~~
~~~
# Restart the container to keep the VPN token valid.
*/5 * * * * /$HOME/motion-pro-vpn-client/check-vpn-status.sh
~~~

### 6. Access Target environment
~~~
podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'
~~~
