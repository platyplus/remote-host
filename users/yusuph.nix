{ config, lib, pkgs, ... }:

{
  users.extraUsers.yusuph = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "docker" ];
    openssh.authorizedKeys.keyFiles = [ ../keys/yusuph ];
  };
}
