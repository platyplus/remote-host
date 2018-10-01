# NixOS
NixOS config for remote servers with little connectivity and available skills.

1. [Installing NixOS from scratch](#method-1-installing-nixos-from-scratch)
2. [Converting an existing Linux system into NixOS](#method-2-converting-an-existing-linux-system-into-nixos)
3. [Creating an encrypted data partition](#creating-an-encrypted-data-partition)

## Method 1: Installing NixOS from scratch

### Prepare a bootable USB key
TODO
https://nixos.org/nixos/download.html

### Run the installation script
```sh
curl https://raw.githubusercontent.com/platyplus/NixOS/master/pre-install.sh | bash
nixos-install --no-root-passwd --max-jobs 4
```
Or if you want to specify a graphql endpoint:
```sh
curl https://raw.githubusercontent.com/platyplus/NixOS/master/pre-install-pre.sh | bash https://endpoint.com
nixos-install --no-root-passwd --max-jobs 4
```
TODO: network...

Remove the USB key and reboot the system

### Run the post-installation script
ssh from the tunnel?
```sh
ssh xxx@platyplus.io -p 2222
sh /etc/nixos/post-install.sh
```

## TODO: simplify what's below
## Method 2: Converting an existing Linux system into NixOS

We don't need a swap partition since we use zram swap on NixOS, we'll thus delete the swap partition and add the extra space to the root partition.

Usually the swap device is in the LVM partition, use `lvdisplay` to identify it (and note down the root partition too), then run

```
sudo swapoff <swap device>
sudo lvremove <swap device>
sudo lvextend -l +100%FREE <root device>
sudo resize2fs <root device>
```
Set labels for the partitions
```
sudo e2label <root device> nixos_root
sudo e2label <boot device> nixos_boot
```
We'll also convert the boot partition from ext2 to ext4 (if needed)
```
sudo umount /boot/
sudo tune2fs -O extents,uninit_bg,dir_index,has_journal /dev/disk/by-label/nixos_boot
sudo fsck.ext4 -vf /dev/disk/by-label/nixos_boot
```

Change the filesystem type in `/etc/fstab` and remount with `mount -a`.

Then we'll follow the steps from [here](https://nixos.org/nixos/manual/index.html#sec-installing-from-other-distro):

```
bash <(curl https://nixos.org/nix/install)
. $HOME/.nix-profile/etc/profile.d/nix.sh
nix-channel --add https://nixos.org/channels/nixos-18.03 nixpkgs
nix-channel --update
nix-env -iE "_: with import <nixpkgs/nixos> { configuration = {}; }; with config.system.build; [ nixos-generate-config nixos-install nixos-enter manual.manpages ]"
sudo `which nixos-generate-config` --root /
```

Edit `/etc/nixos/hardware-configuration.nix` and make sure that no swap device is mentionned and remove any spurious partitions left over from the previous Linux version (like `/var/lib/lxcfs`).

Next, run the steps to download the NixOS config from [this section](#installing-the-os) (but do not run the installer as instructed there!!) and put the config in `/etc/nixos`. Note that we are not mounting the filesystem under `/mnt/` here but working directly in `/etc/`. This is also the time to make any modifications to the config before we build it.

Then we'll go ahead and built the final NixOS system and setup the necessary files to have the conversion done on the next boot.
```
nix-env -p /nix/var/nix/profiles/system -f '<nixpkgs/nixos>' -I nixos-config=/etc/nixos/configuration.nix -iA system
sudo chown -R 0.0 /nix/
sudo chmod 1777 /nix/var/nix/profiles/per-user/
sudo chmod 1777 /nix/var/nix/gcroots/per-user/
sudo touch /etc/NIXOS
echo etc/nixos | sudo tee -a /etc/NIXOS_LUSTRATE
sudo mkdir /boot_old
sudo mv -v /boot/* /boot_old/
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration boot
```
*Note down the current IP address*, this will allow you to connect via ssh in a bit, use `ip addr` to find the current address.

*!!Very important!!*
If you are converting a system to which you do not have direct ssh access and which can only be accessed via a tunnel, you need to make sure that the tunnel service will work after the reboot!

To do so, make sure that the private key to log on to the ssh relay is already present at `/etc/nixos/local/id_tunnel` at this point and that the corresponding public key is enabled on the relay servers.
*!!Verify this very carefully, otherwise you will lock yourself out of the system!!*

Reboot and you should end up in a NixOS system! The old contents of the root directory can be found at `/old_root/`.

Now follow [the final steps of the general installation guide](#final-steps-after-booting-the-os).

## Creating an encrypted data partition

Create the data partition, using up the remaining space in the volume group
```
sudo lvcreate -l 100%FREE -n nixos_data LVMVolGroup
```

Create the encrypted LUKS volume on top of this, use a *strong* passphrase, preferably 128 characters and randomly generated by a password manager. Make sure to store this passphrase securely in the password manager!
```
sudo cryptsetup -v --cipher aes-xts-plain64 --key-size 512 --hash sha512 --use-random luksFormat --type luks2 /dev/LVMVolGroup/nixos_data
```

Next, we open the volume and create a filesystem on it
```
sudo cryptsetup open /dev/LVMVolGroup/nixos_data nixos_data_decrypted
sudo mkfs.ext4 -L nixos_data /dev/mapper/nixos_data_decrypted
sudo tune2fs -m 0 /dev/disk/by-label/nixos_data
```

We will mount the encrypted filesystem on `/opt`
```
sudo mkdir /opt
sudo mount /dev/disk/by-label/nixos_data /opt
```

Next we will bind mount `/var/lib/docker` into the encrypted volume on `/opt/docker`. Make sure docker is not running, if it is run these commands first:
```
sudo systemctl stop docker.socket
sudo systemctl stop docker.service
sudo rm -r /var/lib/docker/
```
Otherwise or after this, we can create the mount
```
sudo mkdir /opt/docker
sudo mkdir /var/lib/docker
sudo mount --bind /opt/docker/ /var/lib/docker
```

Finally, we will add a keyfile to be able to unlock the encrypted volume automatically on boot
```
sudo dd bs=512 count=4 if=/dev/urandom of=/keyfile
sudo chown root:root /keyfile
sudo chmod 0600 /keyfile

sudo cryptsetup luksAddKey /dev/LVMVolGroup/nixos_data /keyfile
```

Now enable `crypto.nix` in `settings.nix` to have automounting at boot time and reboot to test.
