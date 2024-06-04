#!/bin/bash

# WARNING: This script assumes Debian Bookworm 64 bits is used

if [ -z "$SUDO_USER" ]; then
    printf "You must call this script with sudo: sudo ./%s\n" "$(basename "$0")"
    exit 1
fi

function update() {
    # if commented or exists -> do nothing -> return false (1)
    # if doesn't exist -> add it -> return true (0)
    grep "^#.*$1" $2 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
	grep "^$1" $2 2>&1 >/dev/null
	if [ $? -ne 0 ]; then
	    echo "$1" >> $2
	    return 0
	fi
    fi
    return 1
}

function insert() {
    # if commented -> add it
    # if doesn't exist -> add it
    # if exists -> do nothing
    grep "^$1" $2 2>&1 >/dev/null
    if [ $? -ne 0 ]; then
	echo "$1" >> $2
    fi
}

insert "dtparam=spi=on" /boot/firmware/config.txt
insert "dtparam=i2c_arm=on" /boot/firmware/config.txt
insert "gpio=8=pd" /boot/firmware/config.txt
insert "gpio=16=pu" /boot/firmware/config.txt # Fix for SPI IRQ high usage
insert "dtoverlay=gpio-poweroff,gpiopin=23,active_low" /boot/firmware/config.txt
insert "dtoverlay=gpio-shutdown,gpio_pin=24,gpio_pull=up" /boot/firmware/config.txt
insert "dtoverlay=spi0-2cs,cs0_pin=7,cs1_pin=8" /boot/firmware/config.txt
update "dtoverlay=w5500,cs=0,int_pin=6,speed=10000000" /boot/firmware/config.txt
update "dtoverlay=i2c-rtc,ds3231" /boot/firmware/config.txt
update "dtoverlay=sc16is752-spi1-rpiplc-v4,xtal=14745600" /boot/firmware/config.txt

update "enable_uart=1" /boot/firmware/config.txt
sed -i 's/console=serial0,115200 //' /boot/firmware/cmdline.txt

insert "i2c-dev" /etc/modules

if [ ! -f /etc/network/interfaces.d/eth0_1 ]; then
    cat > /etc/network/interfaces.d/eth0_1 << EOT
auto eth0:1
allow-hotplug eth0:1
iface eth0:1 inet static
	address 10.10.10.20
	netmask 255.255.255.0
EOT
fi

if [ ! -f /etc/network/interfaces.d/eth1_1 ]; then
    cat > /etc/network/interfaces.d/eth1_1 << EOT
auto eth1:1
allow-hotplug eth1:1
iface eth1:1 inet static
	address 10.10.11.20
	netmask 255.255.255.0
EOT
fi

[ ! -d /home/$SUDO_USER/.ssh ] && mkdir /home/$SUDO_USER/.ssh && chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.ssh
[ ! -f /home/$SUDO_USER/.ssh/authorized_keys ] && touch /home/$SUDO_USER/.ssh/authorized_keys && chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.ssh/authorized_keys && chmod 600 /home/$SUDO_USER/.ssh/authorized_keys
update "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDCmUlYcl2AIROXD6US8s6D+IFU/Mau3TLuo$SUDO_USERhv5t6V0O+u0zoDEvAurC2xP1xf0mLabaIkFxGgixeSvaGrIqy1oPP30ly8f+zMKe0P9k41D+Lq8ZR9ohdTivlZm5MfW4l6xV6jojWPZNafMn+WW7trfRP/XRxKzcz2mjU9GMLHQmxHqBCsqlnUYkIH0Hq+3xwj9U/IJqYiQD5cm9mtXNLhwK7fYS81GPJhE9bNrJ7B/gmvVw0/3JMCK08DcbUOfHoCvJVbYCdZOM3x$SUDO_USERBtnmtLVD9YWn49yXXDg7Ndipq+tYIpg78HLJkhl31wvXiuKZKne/+sCtWArWZkrLdtLhn $SUDO_USER@raspberrypi" /home/$SUDO_USER/.ssh/authorized_keys

systemctl enable ssh

apt update

RPISHUTDOWN_STATUS=0
mkdir -p /etc/rpishutdown/hooks
systemctl status rpishutdown-pre-poweroff 2>/dev/null
[ $? -eq 0 ] && RPISHUTDOWN_STATUS=1 && systemctl stop rpishutdown-pre-poweroff
curl -L https://apps.industrialshields.com/main/rpi_experimental/rpiplc/rpishutdown-pre-poweroff.service \
     -o /lib/systemd/system/rpishutdown-pre-poweroff.service
curl -L https://apps.industrialshields.com/main/rpi_experimental/rpiplc/check-pre-poweroff-hook.sh \
     -o /etc/rpishutdown/hooks/check-pre-poweroff
chmod ugo+x /etc/rpishutdown/hooks/check-pre-poweroff
if [ ${RPISHUTDOWN_STATUS} -eq 1 ]; then
    systemctl daemon-reload && systemctl start rpishutdown-pre-poweroff
fi
systemctl enable rpishutdown-pre-poweroff

HWCONFIG_STATUS=0
systemctl status hw-config 2>/dev/null
[ $? -eq 0 ] && HWCONFIG_STATUS=1 && systemctl stop hw-config
curl -L https://apps.industrialshields.com/main/rpi_experimental/rpiplc/hw-config.service \
     -o /lib/systemd/system/hw-config.service
curl -L https://apps.industrialshields.com/main/rpi_experimental/rpiplc/blobs64/hw-config -o /usr/local/bin/hw-config
chmod ugo+x /usr/local/bin/hw-config
if [ ${HWCONFIG_STATUS} -eq 1 ]; then
    systemctl daemon-reload && systemctl start hw-config
fi
systemctl enable hw-config.service

# Download SC16IS752 dtbo
curl -L https://apps.industrialshields.com/main/rpi/rpiplc_click_v4/sc16is752-spi1-rpiplc-v4.dtbo -o /boot/overlays/sc16is752-spi1-rpiplc-v4.dtbo


# Install our libraries (and extra libraries for our testers)
apt install -y python3-pip python3-serial python3-websockets python3-aiofiles

# Build the librpiplc library
apt install git cmake -y
git clone -b v3.0.2 https://github.com/Industrial-Shields/librpiplc.git
cd librpiplc/
cmake -B build/ -DPLC_VERSION=RPIPLC_V6 -DPLC_MODEL=ALL
cmake --build build/ -- -j $(nproc)
cmake --install build/
ldconfig
chown -R $SUDO_USER:$SUDO_USER ~/test/
mv ~/test /home/$SUDO_USER/test
chown -R $SUDO_USER:$SUDO_USER .
cd ..

# Install the python3-librpiplc library
git clone -b v3.0.2 https://github.com/Industrial-Shields/python3-librpiplc
cd python3-librpiplc
python -m pip install . --break-system-packages --root-user-action=ignore
chown -R $SUDO_USER:$SUDO_USER .
cd ..


# Bullseye doesn't need it
sed -i -e "/^if \[ -e \/run\/systemd\/system \].*/,+2 s/^/# /" /lib/udev/hwclock-set

# Install Node-RED
LINE=$(echo "127.0.0.1 $(hostname)")
sed -i "1i${LINE}" /etc/hosts
bash <(curl -sL https://raw.githubusercontent.com/node-red/linux-installers/master/deb/update-nodejs-and-nodered) << EOT
y
y
y
EOT
sed -i "/${LINE}/d" /etc/hosts

npm install --prefix /home/$SUDO_USER/.node-red node-red-dashboard
systemctl enable nodered.service

# Other goodies
apt install -y ppp ppp-dev i2c-tools
cd ~
umask 022

apt-get clean

sync

reboot