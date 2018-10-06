
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
        description = "System sync from github configuration repository";
        script = ''
            cd /etc/nixos
            if [ ! -d .git ]; then
                ${pkgs.git}/bin/git init .
                ${pkgs.git}/bin/git remote add origin "https://github.com/${(import ./settings.nix).github_repository}"
            fi
            ${pkgs.git}/bin/git fetch
            if [[ $(${pkgs.git}/bin/git rev-parse HEAD) != $(${pkgs.git}/bin/git rev-parse @{u}) ]]; then
                ${pkgs.git}/bin/git pull --rebase
                echo "Changes pulled"
                touch /var/sync-config.lock
            fi
            echo "Connecting to the cloud server to get the settings file..."
            endpoint=${(import ./settings.nix).api_endpoint}/host-settings
            credentials="${(import ./settings.nix).hostname}:$(cat ./local/service.pwd)"
            status_code=$(curl -u "$credentials" -H 'Cache-Control: no-cache' --silent -o /dev/null --head --write-out '%{http_code}\n' $endpoint)
            ${pkgs.curl}/bin/curl -u "$credentials" -H 'Cache-Control: no-cache' --silent $endpoint # TODO:remove
            if [ $status_code == "200" ]; then
                SETTINGS=$(${pkgs.curl}/bin/curl -u "$credentials" -H 'Cache-Control: no-cache' --silent $endpoint)
                if [ -n "$SETTINGS" ] && [ "$SETTINGS" != 'null' ]; then # TODO: && different from the existing file
                    echo "$SETTINGS" > /etc/nixos/settings # TODO: .nix
                    echo "Pushed the new configuration from the server."
                    touch /var/sync-config.lock
                fi
            fi
            if [ -f /var/sync-config.lock ]; then
                echo "Rebuilding NixOS..."
                ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --upgrade --no-build-output
                rm /var/sync-config.lock
                echo "Finished upgrading NixOS"
            fi
        '';

        restartIfChanged = false;
        unitConfig.X-StopOnRemoval = false;

        serviceConfig.Type = "oneshot";

        environment = config.nix.envVars //
            { inherit (config.environment.sessionVariables) NIX_PATH;
            HOME = "/root";
            } // config.networking.proxy.envVars;

        path = [ pkgs.gnutar pkgs.xz.bin pkgs.curl pkgs.jq config.nix.package.out ];

        # startAt = "*-*-* *:00/15:00";     
        startAt = "*-*-* *:*:00/30";     
    };   
}

