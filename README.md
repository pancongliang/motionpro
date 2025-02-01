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
podman exec -it VPNcontainer /bin/bash
[root@b1c83b17cb9f /]# ssh-keygen
[root@b1c83b17cb9f /]# ssh-copy-id root@10.184.134.128
[root@b1c83b17cb9f /]# exit
~~~

~~~
crontab -e
~~~
~~~
# Restart the container to keep the VPN token valid.
*/5 * * * * /usr/bin/podman exec -it VPNcontainer ssh -o BatchMode=yes -o ConnectTimeout=15 -t root@10.184.134.128 'date' && echo "$(date): SSH Succeeded" >> /var/log/ssh.log 2>&1 || { echo "$(date): SSH Failed" >> /var/log/ssh.log 2>&1; /bin/systemctl restart VPNcontainer.service && echo "$(date): VPNcontainer restarted" >> /var/log/ssh.log 2>&1; }
~~~

### 6. Access Target environment
~~~
podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'
~~~
