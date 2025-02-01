#!/bin/bash
RUNIT='MotionPro_Linux_RedHat_x64_build-8383-30.sh'
if test -f "$RUNIT"; then
   echo "$RUNIT exists."
else
   wget --no-check-certificate -N https://support.arraynetworks.net/prx/000/http/supportportal.arraynetworks.net/downloads/pkg_9_4_5_8/MP_Linux_1.2.18/$RUNIT
fi

podman build -t motion-pro-vpn-client .

read -p "Remove file $RUNIT (y)? " RESP
if [ "$RESP" = "y" ]; then
    rm $RUNIT
    echo "File $RUNIT REMOVED"
else
    echo "Leaving file $RUNIT"
fi
