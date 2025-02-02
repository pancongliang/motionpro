# motion-pro-vpn-client

### 1. Install podman

~~~
git clone https://github.com/pancongliang/motion-pro-vpn-client.git

yum install -y podman wget
podman login registry.redhat.io
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

- Option A: Only containers can access the VPN network
~~~
./runit.sh 
~~~


- Option B: Share VPN network between host and container
~~~
export NETWORK="10.72.94.0/24"
export GATEWAY="10.72.94.254"
export INTERFACE="ens192"

ip rule add from $NETWORK table 100
ip route add default via $GATEWAY dev $INTERFACE table 100

cat << EOF > /etc/rc.d/rc.local
#!/bin/bash
ip rule add from $NETWORK table 100
ip route add default via $GATEWAY dev $INTERFACE table 100
EOF

chmod +x /etc/rc.d/rc.local

./runit-host-network.sh 
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
# Option A: Only containers can access the VPN network
podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'

# Option B: Share VPN network between host and container
ssh root@10.184.134.128
~~~
