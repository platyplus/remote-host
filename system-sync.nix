
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
            ${pkgs.git}/bin/git fetch
            if [[ $(${pkgs.git}/bin/git rev-parse HEAD) != $(${pkgs.git}/bin/git rev-parse @{u}) ]]; then
                ${pkgs.git}/bin/git reset --hard HEAD
                ${pkgs.git}/bin/git checkout --force --track origin/master  # Force to overwrite local files
                ${pkgs.git}/bin/git pull --rebase
                echo "git finished"
                nixos-rebuild switch --upgrade
                echo "rebuild finished"
            fi
        '')
    ];

    services.cron = {
        enable = true;
        systemCronJobs = [
            "*/5 * * * *      root    update-nixos-configuration >> /tmp/update-nixos-configuration.log"
        ];
    };

}

