
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
    systemd.services.syncSystem = {
        # environment = config.nix.envVars //
        # { inherit (config.environment.sessionVariables) NIX_PATH;
        #   HOME = "/root";
        # } // config.networking.proxy.envVars;

        script = ''
            cd /etc/nixos
            if [ ! -d .git ]; then
                ${pkgs.git}/bin/git init .
                ${pkgs.git}/bin/git remote add origin "https://github.com/${(import ./settings.nix).github_repository}"
            fi
            ${pkgs.git}/bin/git fetch && ${pkgs.git}/bin/git pull
            ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --upgrade --no-build-output
        '';
        description = "NixOS Upgrade";

        restartIfChanged = false;
        unitConfig.X-StopOnRemoval = false;

        serviceConfig.Type = "oneshot";

        environment = config.nix.envVars //
            { inherit (config.environment.sessionVariables) NIX_PATH;
            HOME = "/root";
            } // config.networking.proxy.envVars;

        path = [ pkgs.gnutar pkgs.xz.bin config.nix.package.out ];


        startAt = optional "*-*-* *:*:00";        
}

