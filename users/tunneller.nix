{ config, lib, pkgs, ... }:

{
  users.extraUsers.tunneller = {
    isNormalUser = false;
    isSystemUser = true;
    shell = pkgs.nologin;
    openssh.authorizedKeys.keyFiles = [
      ../keys/pilou
      ../keys/yusuph
    ];
  };
}
