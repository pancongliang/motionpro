## Motion Pro VPN Client


### 1. Download the project code
* Download motion-pro-vpn-client repository:
  
  ~~~
  git clone https://github.com/pancongliang/motion-pro-vpn-client.git
  ~~~

### 2. Install required packages and Login to the registry:

* Install podman and wget:
  ~~~
  yum install -y podman wget
  ~~~

* Login to the registry.redhat.io:
  ~~~
  podman login registry.redhat.io
  ~~~

### 3. Build Dockerfile

* Build the Docker Image:
  ~~~
  cd motion-pro-vpn-client
  sh buildit.sh
  ~~~

### 4. Setting Environment Variables

* Test VPN speed:
  ~~~
  sh ping-vpn.sh
  ~~~

* Set required variables:
  ~~~
  export USER='xxxx@xxx.com'
  export PASSWD='xxxx'
  export HOST='pn.sng01.softlayer.com'
  export METHOD=radius
  ~~~


### 5. Start VPNcontainer Container

* Option A: Only containers can access the VPN network:
  ~~~
  sh runit.sh 
  ~~~

* Option B: Share VPN network between host and container:
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

  sh runit-host-net.sh 
  ~~~

### 6. Automatic Start VPN Container

* Automatically start VPN container when the machine starts:
  ~~~
  cp VPNcontainer.service /etc/systemd/system/VPNcontainer.service
  systemctl enable VPNcontainer.service --now
  ~~~

* Restart the container to keep the VPN token valid:
  ~~~
  crontab -e
  # Restart the container to keep the VPN token valid.
  */5 * * * * /$HOME/motion-pro-vpn-client/check-vpn-status.sh

  chmod +x /$HOME/motion-pro-vpn-client/check-vpn-status.sh
  touch /var/log/motionpro.log && chmod 777 /var/log/motionpro.log
  ~~~

### 7. Access the Target Environment

* Option A: Only containers can access the VPN network:
  ~~~
  podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'
  ~~~
  
* Option B: Share VPN network between host and container:
  ~~~
  ssh root@10.184.134.128
  ~~~
