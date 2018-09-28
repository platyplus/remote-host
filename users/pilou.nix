{ config, lib, pkgs, ... }:

{
  users.extraUsers.pilou = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    openssh.authorizedKeys.keyFiles = [ ../keys/pilou ];
  };
}
