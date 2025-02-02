# Motion Pro VPN Client

## 1. Download the Project Code
Clone the repository:
```sh
git clone https://github.com/pancongliang/motion-pro-vpn-client.git
```

## 2. Install Podman and Login to Registry
Install required packages:
```sh
yum install -y podman wget
```

Login to the registry:
```sh
podman login registry.redhat.io
```

## 3. Build the Docker Image
```sh
cd motion-pro-vpn-client
./buildit.sh
```

## 4. Set Environment Variables
Test VPN speed:
```sh
bash ping-vpn.sh
```

Set required variables:
```sh
export USER='xxxx@xxx.com'
export PASSWD='xxxx'
export HOST='pn.sng01.softlayer.com'
export METHOD=radius
```

## 5. Start VPN Container

### Option A: VPN for Containers Only
```sh
./runit.sh
```

### Option B: Share VPN with Host
```sh
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
```

## 6. Enable Automatic Startup
Start VPN container at boot:
```sh
cp VPNcontainer.service /etc/systemd/system/VPNcontainer.service
systemctl enable VPNcontainer.service --now
```

Restart container periodically to keep VPN token active:
```sh
crontab -e
# Restart every 5 minutes
d */5 * * * * /$HOME/motion-pro-vpn-client/check-vpn-status.sh

chmod +x /$HOME/motion-pro-vpn-client/check-vpn-status.sh
touch /var/log/motionpro.log && chmod 777 /var/log/motionpro.log
```

## 7. Access the Target Environment

### Option A: VPN for Containers Only
```sh
podman exec -it VPNcontainer /bin/bash -c 'ssh root@10.184.134.128'
```

### Option B: Share VPN with Host
```sh
ssh root@10.184.134.128
```

