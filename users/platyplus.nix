{ config, lib, pkgs, ... }:

{
  users.extraUsers.platyplus = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # python2 -c 'import crypt, getpass,os,base64; print crypt.crypt(getpass.getpass(), "$6$"+base64.b64encode(os.urandom(16))+"$")'
    # openssl passwd -1 -salt xyz password
    hashedPassword = "$1$4=diwou7$lfa6ztu7qd3agYtGlxqJl/";
    openssh.authorizedKeys.keyFiles = [];
  };
}

