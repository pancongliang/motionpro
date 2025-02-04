## Motion Pro VPN Client


### 1. Download the project code and MotionPro 
* Download motion-pro-vpn-client repository:
  
  ~~~
  git clone https://github.com/pancongliang/motion-pro-vpn-client.git

  curl -sOL https://support.arraynetworks.net/prx/000/http/supportportal.arraynetworks.net/downloads/pkg_9_4_5_8/MP_Linux_1.2.18/MotionPro_Linux_RedHat_x64_build-8383-30.sh
  ~~~

### 2. Install MotionPro Client

* Install MotionPro Client:
  ~~~
  chmod +x MotionPro_Linux_RedHat_x64_build-8383-30.sh
  sh MotionPro_Linux_RedHat_x64_build-8383-30.sh
  ~~~

### Add routing rules

* Add routing rules to access MotionPro client through ssh
  ~~~
  export NETWORK="10.72.94.0/24"
  export GATEWAY="10.72.94.254"
  export INTERFACE="ens192"
  export DNS="10.72.17.5"

  # Temporary
  ip rule add from $NETWORK table 100"  # In order to access the host after opening the VPN
  ip route add default via $GATEWAY dev $INTERFACE table 100  # In order to access the host after opening the VPN
  ip route add $DNS via 10.72.94.254 dev ens192   # In order to access own DNS after opening the VPN

  # Persistent
  echo "ip route add $DNS via 10.72.94.254 dev ens192" >> /etc/rc.d/rc.local
  echo "ip rule add from $NETWORK table 100" >> /etc/rc.d/rc.local
  echo "ip route add default via $GATEWAY dev $INTERFACE table 100" >> /etc/rc.d/rc.local

  # ip route add 10.74.208.0/21 via $GATEWAY dev ens192
  # echo "ip route add 10.74.208.0/21 via $GATEWAY dev $INTERFACE" >> /etc/rc.d/rc.local
  chmod +x /etc/rc.d/rc.local
  ~~~

### 6. Automatic Start MotionPro

* Set required variables:
  ~~~
  cd motion-pro-vpn-client
  vim MotionPro.service

  export USER='xxxx@xxx.com'
  export PASSWD='xxxx'
  export HOST='vpn.sng01.softlayer.com'
  export METHOD=radius
  ~~~

* Execute the script to generate systemd service
  ~~~
  source MotionPro.service
  ~~~

* Restart the container to keep the VPN token valid:
  ~~~
  cd motion-pro-vpn-client
  vim check-motionpro-status.sh

  export USER='xxxx@xxx.com'
  export PASSWD='xxxx'
  export HOST='vpn.sng01.softlayer.com'
  export METHOD=radius

  crontab -e
  # Restart the container to keep the VPN token valid.
  */5 * * * * /$HOME/motion-pro-vpn-client/check-motionpro-status.sh

  chmod +x /$HOME/motion-pro-vpn-client/check-motionpro-status.sh
  touch /var/log/motionpro.log && chmod 777 /var/log/motionpro.log
  ~~~
