#!/bin/bash

set -o nounset
set -o errexit

# Local and host tap interfaces
local_tap_interface=tap1
host_tap_interface=eth1

# Local and host gateway addresses
local_gateway="10.0.75.1/24"
host_gateway="10.0.75.2"
host_netmask="255.255.255.252"

# Permit access to the tap device by user
# TODO check if it's done
# TODO restart docker if it's started and we need to change the owner
sudo chown $USER /dev/$local_tap_interface

# Startup local and host tuntap interfaces
sudo ifconfig $local_tap_interface $local_gateway up
docker run --rm --privileged --net=host --pid=host alpine ifconfig $host_tap_interface $host_gateway netmask $host_netmask up

# Routes for the existing docker networks
subnets=$(docker network inspect -f "{{range .IPAM.Config}}{{.Subnet}}{{end}}" $(docker network ls -f driver=bridge -q))

for subnet in $subnets
do
  echo "Adding route for $subnet via $hostGateway"
  sudo route add $subnet $hostGateway
  echo
done
