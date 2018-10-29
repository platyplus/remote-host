#!/bin/bash
set -e # stop script on error
CONFIG_DIRECTORY=/mnt/etc/nixos
GITHUB_REPO=remote-host
GITHUB_ORG=platyplus
[ -z "$API_ENDPOINT" ] && API_ENDPOINT=https://graphql.platyplus.io
[ -z "$TGTDEV" ] && TGTDEV=/dev/sda

function create_partitions() {
  # TODO mute fdisk
  sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk ${TGTDEV}
    o # clear the in memory partition table
    n # new partition
    p # primary partition
    1 # partition number 1
      # default - start at beginning of disk 
    +1G # 1 GB boot parttion
    n # new partition
    p # primary partition
    2 # partion number 2
      # default, start immediately after preceding partition
      # default, extend partition to end of disk
    t # change type of partition
    2 # select partition number 2
    8e # select LVM type
    p # print the in-memory partition table
    w # write the partition table
    q # and we're done
EOF
  # Create the LVM volumes
  pvcreate ${TGTDEV}2
  vgcreate LVMVolGroup ${TGTDEV}2
  lvcreate -l 100%FREE -n nixos_root LVMVolGroup
  # Format the partitions
  mkfs.ext4 -L nixos_boot ${TGTDEV}1
  mkfs.ext4 -L nixos_root /dev/LVMVolGroup/nixos_root
}

function prepare_os() {
  mount /dev/disk/by-label/nixos_root /mnt
  mkdir /mnt/boot
  mount /dev/disk/by-label/nixos_boot /mnt/boot
  nixos-generate-config --root /mnt
  curl -L "https://github.com/$GITHUB_ORG/$GITHUB_REPO/archive/master.zip" --output /tmp/config.zip
  cd /tmp
  unzip config.zip
  mv $GITHUB_REPO-master/* "$CONFIG_DIRECTORY"
  mv $GITHUB_REPO-master/.gitignore "$CONFIG_DIRECTORY"

  # Local settings: settings that are dependent to the hardware and therefore that
  # are not required to store on the cloud server if we need to reinstall on new hardware
  cp "$CONFIG_DIRECTORY/settings-hardware.nix.template" "$CONFIG_DIRECTORY/settings-hardware.nix"

  # Find a stable device name for grub and set it in the configuration
  DEVICEID=`ls -l /dev/disk/by-id/ | grep "${TGTDEV##*/}$" | awk '{print $9}'`
  sed -i -e 's/{{device}}/'"${DEVICEID//\//\\/}"'/g' "$CONFIG_DIRECTORY/settings-hardware.nix"

  # Install the programms required to run the script
  nix-env -iA nixos.jq
}

function graphql_query() {
    if [ -z "$TOKEN" ]
    then
        curl -s $API_ENDPOINT -H 'Content-Type: application/json' --compressed \
            --data-binary '{"query":"{ \n '"$1"' ('"$2"') '"$3"' \n}\n"}'
    else
        curl -s $API_ENDPOINT -H 'Content-Type: application/json' --compressed \
            -H "Authorization: Bearer $TOKEN" \
            --data-binary '{"query":"{ \n '"$1"' ('"$2"') '"$3"' \n}\n"}'
    fi
}

function graphql_mutation() {
    if [ -z "$TOKEN" ]
    then
        curl -s $API_ENDPOINT -H 'Content-Type: application/json' --compressed \
            --data-binary '{"query":"mutation\n{ \n '"$1"' ('"$2"') { '"$3"' } \n}\n"}'
    else
        curl -s $API_ENDPOINT -H 'Content-Type: application/json' --compressed \
            -H "Authorization: Bearer $TOKEN" \
            --data-binary '{"query":"mutation\n{ \n '"$1"' ('"$2"') { '"$3"' } \n}\n"}'
    fi
}

function mutation_upsert_host() {
    graphql_mutation upsertHost 'ownerId:\"'"$1"'\", hostName:\"'"$2"'\", publicKey: \"'"$3"'\", timeZone: \"'"$4"'\"' 'id'
}

function mutation_upsert_user() {
    graphql_mutation upsertUser 'login:\"'"$1"'\", password:\"'"$2"'\", name: \"'"$3"'\" role: SERVICE' 'token\nuser {\nid}'
}

function mutation_login() {
    login=$1
    password=$2
    graphql_mutation signin 'login:\"'"$login"'\", password: \"'"$password"'\"' 'token\n user { role }'
}

function auth_admin() {
    while [ -z "$TOKEN" ]
    do
        [ $LOGIN == '' ] && [ $PASSWORD == '' ] && echo "Please enter an admin login/password"
        while [[ $LOGIN == '' ]]
        do
            read -p "Login: " LOGIN
            [ $LOGIN == '' ] && echo "Should not be empty!"
        done
        while [[ $PASSWORD == '' ]]
        do
            read -sp "Password: " PASSWORD  
            echo
            [ $PASSWORD == '' ] && echo "Should not be empty!"
        done
        DATA_LOGIN=`mutation_login $LOGIN $PASSWORD`
        TOKEN=`echo $DATA_LOGIN | jq '.data.signin.token'`
        if [ -z "$TOKEN" ] || [ "$TOKEN" == '"null"' ]
        then
            echo $DATA_LOGIN
            unset LOGIN PASSWORD TOKEN
        fi
        ROLE=`echo $DATA_LOGIN | jq '.data.signin.user.role'`
        if [ -z "$ROLE" ] || [ "$ROLE" == '"null"' ] || [[ "$ROLE" != '"ADMIN"' ]]
        then
            echo "The user $LOGIN is not an admin"
            unset LOGIN PASSWORD TOKEN
        fi
    done
    TOKEN_ADMIN=${TOKEN:1:${#TOKEN}-2} # trim first and last characters (remaining double quotes from JSON string format)
    unset TOKEN LOGIN PASSWORD DATA_LOGIN
}

function create_service_account() {
    TOKEN=$TOKEN_ADMIN
    MODE=''
    while [[ $NEW_HOSTNAME == '' ]]
    do
        read -p "Hostname of the machine: " NEW_HOSTNAME
        [ $NEW_HOSTNAME == '' ] && echo "Should not be empty!"
        HOSTID=`graphql_query host 'hostName:\"'"$NEW_HOSTNAME"'\"' "{ id }" | jq '.data.host.id'`
        if [ -z "$HOSTID" ] || [ "$HOSTID" == 'null' ]
        then
            MODE=CREATE
        else
            choice=N
            echo "A configuration alread exists for the host $NEW_HOSTNAME."
            read -p "Do you want to configure this server from the existing config? (y/N): " choice
            [ "$choice" == "y" ] && MODE=UPDATE || unset NEW_HOSTNAME
        fi
    done
    if [[ "$MODE" != '' ]]
    then
        ssh-keygen -a 100 -t ed25519 -N "" -C "service@${NEW_HOSTNAME}" -f "$CONFIG_DIRECTORY/local/id_service"
        PUBLIC_KEY=`cat "$CONFIG_DIRECTORY/local/id_service.pub"`
        PASSWORD=`openssl rand -base64 32` # TODO: Where and how to store it?
        echo $PASSOWRD > "$CONFIG_DIRECTORY/local/service.pwd" && chmod 400 "$CONFIG_DIRECTORY/local/service.pwd"
        if [[ "$MODE" == "CREATE" ]]
        then
            DATA=`mutation_upsert_user "service@$NEW_HOSTNAME" "$PASSWORD" "Service user for host $NEW_HOSTNAME"`
            # TODO: catch errors
            USERID=`echo $DATA | jq '.data.upsertUser.user.id' | sed -e 's/^"//' -e 's/"$//'`
            TOKEN_SERVICE=`echo $DATA | jq '.data.upsertUser.token' | sed -e 's/^"//' -e 's/"$//'`
            read -p "Time zone (default: Europe/Brussels): " TIMEZONE
            [ "$TIMEZONE" == '' ] && TIMEZONE="Europe/Brussels"
        elif [[ "$MODE" == "UPDATE" ]]
        then
            echo "TODO: update mode"
        fi
        DATA=`mutation_upsert_host "$USERID" "$NEW_HOSTNAME" "$PUBLIC_KEY" "$TIMEZONE"`
        HOSTID=`echo "$DATA" | jq '.data.upsertHost.id'`
        if [ -z "$HOSTID" ] || [ "$HOSTID" == 'null' ]
        then
            echo "Error in updating the configuration"
            echo "$DATA"
            exit
        fi
    fi
    unset TOKEN PUBLIC_KEY TIMEZONE ROLE DATA
}

function update_nix_settings_file() {
    TOKEN=$TOKEN_ADMIN
    DATA=`graphql_query hostSettings 'hostName:\"'"$NEW_HOSTNAME"'\"' | jq '.data'`
    if [ -z "$DATA" ] || [ "$DATA" == 'null' ]; then
        # TODO: handle errors
        echo "Error: $DATA"
    else
        DATA=`echo $DATA | jq '.hostSettings' | sed -e 's/^"//' -e 's/"$//' | base64 --decode`
        echo "$DATA" > "$CONFIG_DIRECTORY/settings.nix"
    fi
    unset TOKEN DATA
}

function update_nix_network_file() {
    TOKEN=$TOKEN_SERVICE
    # TODO: send the information to the server?
    cp "$CONFIG_DIRECTORY/static-network.nix.template" "$CONFIG_DIRECTORY/static-network.nix"

    DEFAULTINTERFACE=`ip route | grep default | awk '{print $5}'`
    read -p "Network interface (default: $DEFAULTINTERFACE): " INTERFACE
    [ "$INTERFACE" == '' ] && INTERFACE=$DEFAULTINTERFACE
    sed -i -e 's/{{interface}}/'"$INTERFACE"'/g' "$CONFIG_DIRECTORY/static-network.nix"

    DEFAULTADDRESS=`ip route | grep default | awk '{print $7}'`
    read -p "IP Address (default: $DEFAULTADDRESS): " ADDRESS
    [ "$ADDRESS" == '' ]] && ADDRESS=$DEFAULTADDRESS
    sed -i -e 's/{{address}}/'"$ADDRESS"'/g' "$CONFIG_DIRECTORY/static-network.nix"

    DEFAULTGATEWAY=`ip route | grep default | awk '{print $3}'`
    read -p "Gateway (default: $DEFAULTGATEWAY): " GATEWAY
    [ "$GATEWAY" == '' ] && GATEWAY=$DEFAULTGATEWAY
    sed -i -e 's/{{gateway}}/'"$GATEWAY"'/g' "$CONFIG_DIRECTORY/static-network.nix"

    echo "IP address: $ADDRESS"
    [ -f "$CONFIG_DIRECTORY/../issue" ] && echo "IP address: $ADDRESS (remove this line from /etc/issue)" >> "$CONFIG_DIRECTORY/../issue"
    unset TOKEN DEFAULTINTERFACE DEFAULTADDRESS
}

# TEST VALUES
# API_ENDPOINT=localhost:5000
# LOGIN=pilou@pilou.com
# PASSWORD=nooneknows
# CONFIG_DIRECTORY=/tmp

create_partitions
prepare_os
auth_admin
create_service_account
update_nix_settings_file
update_nix_network_file

echo "You may now install NixOS in running the command: nixos-install --no-root-passwd --max-jobs 4"
