
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
    environment.systemPackages = [
        (pkgs.writeShellScriptBin "update-nixos-configuration" ''
            cd /etc/nixos
            if [ ! -d .git ]; then
                ${pkgs.git}/bin/git init .
                ${pkgs.git}/bin/git remote add origin "https://github.com/${(import ./settings.nix).github_repository}"
            fi
            ${pkgs.git}/bin/git fetch && ${pkgs.git}/bin/git pull
            # if [[ $(${pkgs.git}/bin/git rev-parse HEAD) != $(${pkgs.git}/bin/git rev-parse @{u}) ]]; then
            #     ${pkgs.git}/bin/git reset --hard HEAD
            #     ${pkgs.git}/bin/git checkout --force --track origin/master  # Force to overwrite local files
            #     ${pkgs.git}/bin/git pull --rebase
            # fi
        '')
    ];

    systemd.services.syncSystem = {
        environment = config.nix.envVars //
        { inherit (config.environment.sessionVariables) NIX_PATH;
          HOME = "/root";
        } // config.networking.proxy.envVars;

        script = "update-nixos-configuration";

        wantedBy = [ "default.target" ];
        };

        systemd.timers.syncSystem = {
        timerConfig = {
            Unit = "syncSystem.service";
            OnCalendar = "*-*-* *:00:00";
        };
        wantedBy = [ "timers.target" ];
        };
        
}

