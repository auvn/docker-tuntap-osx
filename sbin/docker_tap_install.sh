#!/bin/sh

function check_file(){
        ([ ! -z $1 ] && [ -e $1 ] && return 0) || return 1
}

function err() {
        echo $@
        exit 1
}

function ask() {
        local msg=$1
        shift
        local cmd=$@
        echo $msg
        echo " Type \"yes\" and press enter to continue"
        read code
        if [ "$code" = 'yes' ];
        then
                $@
        fi
        echo Skipping.
}

# Folder where this install script resides
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)

TAP_ID="tap1"
TAP_IFACE="/dev/$TAP_ID"
SHIM_FILE="$SCRIPT_DIR/docker.hyperkit.tuntap.sh"

LOCATIONS=( \
        "/Applications/Docker.app/Contents/MacOS/com.docker.hyperkit" \
        "/Applications/Docker.app/Contents/Resources/bin/com.docker.hyperkit" \
        "/Applications/Docker.app/Contents/Resources/bin/hyperkit")

function find_hyperkit(){
        local possible_locations=$(
                for loc in ${LOCATIONS[@]};
                do
                        echo $loc
                        echo $HOME$loc
                done)
        for loc in $possible_locations;
        do
                check_file $loc && echo $loc && break
        done
        echo
}

function restart_hyperkit(){
        echo "Restarting docker..."

        osascript -e 'quit app "Docker"'
        open --background -a Docker

        echo "Waiting for docker to be alive..."

        while true;
        do
                docker version > /dev/null 2>&1 && break || sleep 1
        done
        echo "Done."
}

function replace_hyperkit(){
        check_file $SHIM_FILE || err "Failed to find shim script: $SHIM_FILE"

        local hyperkit_file=$(find_hyperkit)
        check_file $hyperkit_file || err "Failed to find hyperkit file"

        cmp -s $SHIM_FILE $hyperkit_file \
                && echo "Already installed to $hyperkit_file" \
                && return 0

        echo "Replacing hyperkit executable"
        cp $hyperkit_file "${hyperkit_file}.bak.$(date +%Y%m%d_%H%M%S)"
        mv $hyperkit_file "${hyperkit_file}.original"
        cp $SHIM_FILE $hyperkit_file
}

function update_tap_ownership() {
        check_file $TAP_IFACE || err "Failed to find tap device: $TAP_IFACE"

        ifconfig $TAP_ID > /dev/null 2>&1 && return 0

        echo "Updating owner of $TAP_IFACE to $USER"
        sudo chown $USER $TAP_IFACE

        ask "Restart docker?" restart_hyperkit
}

function setup_docker_network(){
        local container_tap_iface=eth1
        local host_gw="10.0.75.1/24"
        local container_gw="10.0.75.2"
        local container_netmask="255.255.255.252"

        echo "Configuring host interface..."
        sudo ifconfig $TAP_ID $host_gw up || err "Failed to setup host interface: $TAP_ID"

        echo "Configuring docker interface..."
        docker run --rm --privileged --net=host --pid=host alpine \
                ifconfig $container_tap_iface $container_gw netmask $container_netmask up \
                || err "Failed to setup docker network interface"

        setup_docker_subnets $container_gw
}

function setup_docker_subnets(){
        local gw=$1
        local subnets=$(docker network inspect -f "{{range .IPAM.Config}}{{.Subnet}}{{end}}" \
                        $(docker network ls -f driver=bridge -q))

        for subnet in $subnets;
        do
                echo "Adding route for $subnet via $gw"
                sudo route add $subnet $gw
                echo
        done
}

function main(){

        replace_hyperkit || err "Failed to replace hyperkit"
        update_tap_ownership || err "Failed to update tap interface ownership"
        setup_docker_network
}

main

