{ config, lib, pkgs, ... }:

{
  users.extraUsers.platyplus = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    # python2 -c 'import crypt, getpass,os,base64; print crypt.crypt(getpass.getpass(), "$6$"+base64.b64encode(os.urandom(16))+"$")'
    hashedPassword = "$1$IwyaeK2S$mTlthniELh8N3fwLVZfPW0";
    openssh.authorizedKeys.keyFiles = [];
  };
}

