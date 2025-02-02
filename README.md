# motion-pro-vpn-client

### 1. Install podman

~~~
git clone https://github.com/pancongliang/motion-pro-vpn-client.git
yum install -y podman wget
~~~

### 2. Build Dockerfile

~~~
cd motion-pro-vpn-client
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
cp VPNcontainer.service /etc/systemd/system/VPNcontainer.service

systemctl enable VPNcontainer.service --now
~~~

#### Restart the container to keep the VPN token valid.
~~~
crontab -e

# Restart the container to keep the VPN token valid.
*/5 * * * * /$HOME/motion-pro-vpn-client/check-vpn-status.sh
~~~

### 6. Access Target environment
~~~
podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'
~~~
