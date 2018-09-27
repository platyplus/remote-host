
########################################################################
#                                                                      #
# DO NOT EDIT THIS FILE, ALL EDITS SHOULD BE DONE IN THE GIT REPO,     #
# PUSHED TO GITHUB AND PULLED HERE.                                    #
#                                                                      #
# LOCAL EDITS WILL BE OVERWRITTEN.                                     #
#                                                                      #
########################################################################

{ config, lib, pkgs, ... }:

{

  # Python is not at /usr/bin/python in NixOS
  # https://github.com/NixOS/nixpkgs/blob/master/pkgs/tools/admin/ansible/2.4.nix
  nixpkgs.config.packageOverrides = super: {
    ansible = super.ansible.overrideAttrs (old: rec {
      version = "2.5.9";
      name = "${old.pname}-${version}";
 
      src = super.fetchurl {
        url = "http://releases.ansible.com/ansible/${name}.tar.gz";
        sha256 = "df986910196093fd0688815e988e205606f7cdec3d1da26d42a5caea8170f2e9";
      };

      prePatch = ''
        sed -i "s,/usr/,$out," lib/ansible/constants.py && \
        find lib/ansible/ -type f -exec sed -i "s,/usr/bin/python,/usr/bin/env python,g" {} \;
      '';
    });
  };

  environment.systemPackages = with pkgs; [
    ansible
    rsync
  ];

}

