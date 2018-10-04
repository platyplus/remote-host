#!/bin/bash
set -e # stop script on error
# TODO

# First check that we are on the correct nix channel
sudo nix-channel --list
# This should show the 18.03 channel with name `nixos`, otherwise we need to add it
sudo nix-channel --add https://nixos.org/channels/nixos-18.03 nixos

# Then we will do a full system update
sudo nixos-rebuild switch --upgrade

# If you just upgraded from an existing Linux system, it's safer to reinstall the bootloader
# once more to avoid issues
#sudo nixos-rebuild switch --upgrade --install-bootloader

# Next, if not already done, we'll put the content of the *public* key file for the reverse
# tunnel (`/etc/nixos/local/id_service.pub`) in the `authorized_keys` file for the tunnel user
# on github (this repo, `keys/tunnel`). (Easiest way is to connect via SSH on the local network
# to copy the key.)
# Then do a `git pull` and a rebuild of the config on the ssh relay servers.

# Finally, we will turn `/etc/nixos` into a git clone of this repository
cd /etc/nixos
git init
git remote add origin https://github.com/platyplus/remote-host
git fetch
git checkout --force --track origin/master  # Force to overwrite local files
git pull --rebase

# Check with `git status` that there are no left-over untracked files, these should probably
# be either deleted or commited.

# You're all done! Refer to Creating an encrypted data partition if you want to set up an
# encrypted data partition.