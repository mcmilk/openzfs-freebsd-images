#!/usr/bin/env bash

######################################################################
# 1) setup the action runner to start some qemu instance
######################################################################

set -eu

# remove unneeded things
sudo apt-get remove google-chrome-stable snapd

# install needed packages
sudo apt-get update
sudo apt-get install axel cloud-image-utils daemonize guestfs-tools \
  virt-manager linux-modules-extra-`uname -r`

sudo fstrim -a
