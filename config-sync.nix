
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
                touch /var/sync-config.lock
                # TODO: remove the line below 
                ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --upgrade --no-build-output
                echo "Changes pulled"
            fi
            if [ -f /var/sync-config.lock ]; then
                endpoint=${(import ./settings.nix).api_endpoint}
                query='{"query":"mutation\n{ \n signin (login: \"service@${(import ./settings.nix).hostname}\", password:\"'"$(cat ./local/service.pwd)"'\") { token } \n}\n"}'
                DATA=$(${pkgs.curl}/bin/curl -s $endpoint -H 'Content-Type: application/json' --compressed --data-binary "$query")
                TOKEN=$(echo $DATA | jq '.data.signin.token' | sed -e 's/^"//' -e 's/"$//')
                query='{"query":"{\n  hostSettings(hostName:\"${(import ./settings.nix).hostname}\")\n}"}'
                DATA=$(${pkgs.curl}/bin/curl -s "$endpoint" -H "Authorization: $TOKEN" -H 'Content-Type: application/json' --compressed --data-binary "$query")
                SETTINGS=$(echo $DATA | jq '.data.hostSettings' | sed -e 's/^"//' -e 's/"$//' | base64 --decode)
                echo TODO: check if SETTINGS is not empty or buggy before replacing the settings file!
                echo $SETTINGS > /tmp/settings
                # echo "Rebuilding NixOS..."
                # ${config.system.build.nixos-rebuild}/bin/nixos-rebuild switch --upgrade --no-build-output
                # echo "Finish upgrading NixOS"
                # rm /var/sync-config.lock
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

