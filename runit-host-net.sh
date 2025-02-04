#!/bin/bash
podman run -d --hostname motion-pro-vpn --name VPNcontainer --privileged --network host -v /root:/host-rootfs motion-pro-vpn-client --method $METHOD --host $HOST --user $USER --passwd $PASSWD -c inf --loglevel warn
