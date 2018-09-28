#!/bin/sh
TGTDEV=/dev/sda
# TODO mute fdisk
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${TGTDEV}
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +1G # 1 GB boot parttion
  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  p # print the in-memory partition table
  w # write the partition table
  q # and we're done
EOF
  # a # make a partition bootable
  # 1 # bootable partition is partition 1 -- /dev/sda1

# Create the LVM volumes
pvcreate ${TGTDEV}2
vgcreate LVMVolGroup ${TGTDEV}2
lvcreate -l 100%FREE -n nixos_root LVMVolGroup
# Format the partitions
mkfs.ext4 -L nixos_boot ${TGTDEV}1
mkfs.ext4 -L nixos_root /dev/LVMVolGroup/nixos_root

# Install the OS
mount /dev/disk/by-label/nixos_root /mnt
mkdir /mnt/boot
mount /dev/disk/by-label/nixos_boot /mnt/boot
nixos-generate-config --root /mnt
curl -L https://github.com/platyplus/NixOS/archive/master.zip --output /tmp/config.zip
cd /tmp
unzip config.zip
mv NixOS-master/* /mnt/etc/nixos
mv NixOS-master/.gitignore /mnt/etc/nixos
# rmdir NixOS-master
cp /mnt/etc/nixos/settings.nix.template /mnt/etc/nixos/settings.nix

# Set the required settings:
# nano /mnt/etc/nixos/settings.nix
# TODO check hostname availability against the Cloud API
NEW_HOSTNAME="testname" # TODO prompt
sed -i -e 's/{{hostname}}/'"$NEW_HOSTNAME"'/g' /mnt/etc/nixos/settings.nix

# Find a stable device name for grub and append it to the settings file for copy/paste:
# Then you can add the path to the grub.device setting.
DEVICEID=`ls -l /dev/ | grep "${TGTDEV##*/}$" | awk '{print $9}'`
sed -i -e 's/{{device}}/'"${DEVICEID//\//\\/}"'/g' /mnt/etc/nixos/settings.nix

TIMEZONE="Europe/Brussels" # TODO prompt
sed -i -e 's/{{timezone}}/'"${TIMEZONE//\//\\/}"'/g' /mnt/etc/nixos/settings.nix
# TODO get tunnel port from the Cloud API
TUNNELPORT=10001 # TODO prompt
sed -i -e 's/{{tunnelport}}/'"$TUNNELPORT"'/g' /mnt/etc/nixos/settings.nix

# Network configuration
cp /mnt/etc/nixos/static-network.nix.template /mnt/etc/nixos/static-network.nix
INTERFACE=`ip route | grep default | awk '{print $5}'` # TODO prompt - eth0?
sed -i -e 's/{{interface}}/'"$INTERFACE"'/g' /mnt/etc/nixos/static-network.nix
ADDRESS=`ip route | grep default | awk '{print $7}'` # TODO prompt
sed -i -e 's/{{address}}/'"$ADDRESS"'/g' /mnt/etc/nixos/static-network.nix
GATEWAY=`ip route | grep default | awk '{print $3}'` # TODO prompt
sed -i -e 's/{{gateway}}/'"$GATEWAY"'/g' /mnt/etc/nixos/static-network.nix

# And if you enabled the reverse tunnel service, generate a key pair for the tunnel:
# TODO use NEW_HOSTNAME instead of HOSTNAME?
ssh-keygen -a 100 -t ed25519 -N "" -C "tunnel@${HOSTNAME}" -f /mnt/etc/nixos/local/id_tunnel

# if the reverse tunnel service is enabled in settings.nix but the private key is not present,
# the build will fail and complain that the file cannot be found.
# Then launch the installer:
nixos-install --no-root-passwd --max-jobs 4

