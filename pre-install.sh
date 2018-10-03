#!/bin/bash
set -e # stop script on error
CONFIG_DIRECTORY=/mnt/etc/nixos
if [ -z "$API_ENDPOINT"]
then
  API_ENDPOINT=https://graphql.platyplus.io
fi
if [ -z "$TGTDEV"]
then
  TGTDEV=/dev/sda
fi
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
  curl -L https://github.com/platyplus/NixOS/archive/master.zip --output /tmp/config.zip
  cd /tmp
  unzip config.zip
  mv NixOS-master/* "$CONFIG_DIRECTORY"
  mv NixOS-master/.gitignore "$CONFIG_DIRECTORY"

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

function mutation_create_user() {
    graphql_mutation createUser 'login:\"'"$1"'\", name:\"'"$2"'\", password: \"'"$3"'\", role: '"$4"', publicKey: \"'"$5"'\", timeZone: \"'"$6"'\"' 'token'
}

function mutation_update_user() {
    ##### TODO: #########
    echo "{}"
}

function mutation_login() {
    login=$1
    password=$2
    graphql_mutation signin 'login:\"'"$login"'\", password: \"'"$password"'\"' 'token\n user { role }'
}

function auth_admin() {
    while [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]
    do
        echo "Please enter an admin login/password"
        while [[ $LOGIN == '' ]]
        do
            read -p "Login: " LOGIN
            if [[ $LOGIN == '' ]]
            then
                echo "Should not be empty!"
            fi
        done
        while [[ $PASSWORD == '' ]]
        do
            read -sp "Password: " PASSWORD  
            echo
            if [[ $PASSWORD == '' ]]
            then
                echo "Should not be empty!"
            fi
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
            echo "The user has the role $ROLE, not \"ADMIN\""
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
        read -p "Hostname of the new machine: " NEW_HOSTNAME
        if [[ $NEW_HOSTNAME == '' ]]
        then
            echo "Should not be empty!"
        fi
        ROLE=`graphql_query users 'login:\"tunnel@'"$NEW_HOSTNAME"'\"' "{ role }" | jq '.data.users[0].role'`
        if [ -z "$ROLE" ] || [ "$ROLE" == 'null' ]
        then
            MODE=CREATE
        else
            if [[ "$ROLE" != "HOST_SERVICE" ]]
            then
                choice=N
                echo "A configuration alread exists for the host $NEW_HOSTNAME."
                read -p "Do you want to configure this server from the existing config? (y/N): " choice
                if [[ "$choice" == "y" ]]
                then
                    MODE=UPDATE
                else
                    echo "Installation stopped."
                fi
            else
                echo "The role of the existing configuration ($ROLE) is not a host service role. Installation stopped."
            fi
        fi
    done
    if [[ "$MODE" != '' ]]
    then
        ssh-keygen -a 100 -t ed25519 -N "" -C "tunnel@${NEW_HOSTNAME}" -f "$CONFIG_DIRECTORY/local/id_tunnel"
        PUBLIC_KEY=`cat "$CONFIG_DIRECTORY/local/id_tunnel.pub"`
        PASSWORD=1234 # TODO autogenerate? Where and how to store it?
        if [[ "$MODE" == "CREATE" ]]
        then
            read -p "Time zone (default: Europe/Brussels): " TIMEZONE
            if [[ "$TIMEZONE" == '' ]]
            then
                TIMEZONE="Europe/Brussels"
            fi
            DATA=`mutation_create_user "tunnel@$NEW_HOSTNAME" "$NEW_HOSTNAME" "$PASSWORD" "HOST_SERVICE" "$PUBLIC_KEY" "$TIMEZONE"`
            TOKEN_SERVICE=`echo "$DATA" | jq '.data.createUser.token'`
        elif [[ "$MODE" == "UPDATE" ]]
        then
            DATA=`mutation_update_user "tunnel@$NEW_HOSTNAME" "$NEW_HOSTNAME" "$PASSWORD" "HOST_SERVICE" "$PUBLIC_KEY"`
            TOKEN_SERVICE=`echo "$DATA" | jq '.data.updateUser.token'`
        fi
        if [ -z "$TOKEN_SERVICE" ] || [ "$TOKEN_SERVICE" == 'null' ]
        then
            echo "Error in updating the configuration"
            echo "$DATA"
            exit
        fi
        TOKEN_SERVICE=${TOKEN_SERVICE:1:${#TOKEN_SERVICE}-2}
        echo $TOKEN_SERVICE
    fi
    unset TOKEN PUBLIC_KEY TIMEZONE ROLE DATA
}

function update_nix_settings_file() {
    TOKEN=$TOKEN_SERVICE
    DATA=`graphql_query hostSettings 'login:\"tunnel@'"$NEW_HOSTNAME"'\"' | jq '.data.hostSettings'`
    if [ -z "$DATA" ] || [ "$DATA" == 'null' ]
    then
        # TODO: handle errors
        echo "error"
    else
        DATA=`echo ${DATA:1:${#DATA}-2} | base64 -D`
        echo "$DATA" > "$CONFIG_DIRECTORY/settings.nix"
    fi
    unset TOKEN DATA
}

# TODO:Network configuration
function update_nix_network_file() {
    TOKEN=$TOKEN_SERVICE
    # cp "$CONFIG_DIRECTORY/static-network.nix.template" "$CONFIG_DIRECTORY/static-network.nix"
    # INTERFACE=`ip route | grep default | awk '{print $5}'` # TODO prompt - eth0?
    # sed -i -e 's/{{interface}}/'"$INTERFACE"'/g' "$CONFIG_DIRECTORY/static-network.nix"
    # ADDRESS=`ip route | grep default | awk '{print $7}'` # TODO prompt
    # sed -i -e 's/{{address}}/'"$ADDRESS"'/g' "$CONFIG_DIRECTORY/static-network.nix"
    # GATEWAY=`ip route | grep default | awk '{print $3}'` # TODO prompt
    # sed -i -e 's/{{gateway}}/'"$GATEWAY"'/g' "$CONFIG_DIRECTORY/static-network.nix"
    unset TOKEN
}

function set_network() {
    # TODO
    TOKEN=$TOKEN_SERVICE
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
# TODO: update_nix_network_file
# TODO: nixos-install --no-root-passwd --max-jobs 4

echo "IP address: $ADDRESS"
